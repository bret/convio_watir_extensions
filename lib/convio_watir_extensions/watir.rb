require 'watir/ie'
require 'convio_watir_extensions/watir_process'
require 'convio_watir_extensions/matches'

module Watir

  at_exit{$watir_socket.stop if $watir_socket}

  module PageContainer
    # Escape quotes for DOS
    alias :old_eval_in_spawned_process :eval_in_spawned_process
    def eval_in_spawned_process(command)
      command.strip!
      load_path_code = _code_that_copies_readonly_array($LOAD_PATH, '$LOAD_PATH')
      ruby_code = "require 'watir/ie'; "
      ruby_code << "pc = #{attach_command}; " # pc = page container
      if Date::parse(RUBY_RELEASE_DATE) >=  Date::parse("2008-01-11")
        ruby_code << "pc.instance_eval(\"#{command}\")"
        exec_string = (load_path_code + '; ' + ruby_code)
        exec_string = "start rubyw -e \"#{exec_string.gsub!('"','"""')}\""
      else
        ruby_code << "pc.instance_eval(#{command.inspect})"
        exec_string = "start rubyw -e #{(load_path_code + '; ' + ruby_code).inspect}"
      end        
      system(exec_string)
    end
    alias :convio_eval_in_spawned_process :eval_in_spawned_process
    def eval_in_spawned_process(command)
      require 'socket'
      begin
        s = TCPSocket.open('localhost', 20000)
        s.puts  "pc = #{attach_command}; pc.instance_eval(#{command.inspect})"
        s.close
      rescue Errno::ECONNREFUSED
        $watir_socket = Watir::SpawnInNewProcess::Server.new
        retry
      end
    end
  end  
  
  
  # The first change allows you to identify elements based on having a cell that matches 
  # the given text. It will return the innermost (most embedded) table with that match. 
  # You could use browser.cells but the problem is that it matches on innerText so if 
  # you have a series of embedded tables, you'll always get the topmost one. While you
  # can have a developer put in a unique identifier to the table, this is not always 
  # as easy with legacy applications. 
  #
  # Syntax:
  # @browser.table(:has_cell, 'cell text')
  # @browser.row(:has_cell, 'cell text')
  #
  # The second change is given a table row, return the cell in the column by name. The
  # assumption is made that the first row in the table represents the column values
  # (and this is only designed for horizontal headers). Given that you can get the 
  # watir cell for a table using: 
  #
  # @browser.row(:has_cell, /some text/).column('Totals')
  #
  # Note that the column doesn't require using :has_cell so you could just as easily do:
  #
  # @browser.row(:text, /some text/).column('Totals')
  
  class TaggedElementLocator
    def locate
      index_target = @specifiers[:index]
      count = 0
      each_element(@tag) do |element|
        catch :next_element do
          @specifiers.each do |how, what|
            next if how == :index
            
            # Look for text in a table cell but continue on
            # if there is a match in an embedded table in that cell
            if how == :has_cell && (match? element, how, what) && element.tables
              element.tables.each {|table| throw :next_element if table.cell(:text, what).exists? }
              next
            end
            
            unless match? element, how, what
              throw :next_element
            end
          end
          
          count += 1
          throw :next_element unless index_target == count
          
          return element.ole_object          
        end
        
      end # elements
      nil
    end
  end
  
  class TableCell < Element
    def locate
      if @how == :xpath
        @o = @container.element_by_xpath(@what)
      elsif @how == :ole_object
        @o = @what
      else
        @o = @container.locate_tagged_element("TD", @how, @what) || @container.locate_tagged_element("TH", @how, @what)
      end
    end
  end
  
  class TableRow < Element
    
    # Return the cell in the row based on the column
    # name, the value from the first row of the table
    def column(name)
      # Create a list of column names from the first row of the table. 
      # If we see any colspans, duplicate the name for each column spanned
      # If the column name given has a colspan we won't know which row cell
      # in the span so we'll return the first one. You can work around this just 
      # getting the row cell by position. 
      column_names = []
      table_node = parent
      while table_node.ole_object.nodeName != 'TABLE'
        table_node = table_node.parent
      end
      first_table_row = table(:ole_object, table_node.ole_object)[1]
      first_table_row.each { |cell| cell.colspan.times {column_names << cell.text} }
      requested_column_index = column_names.matches(name) 
      raise UnknownCellException, "Unable to locate a table cell using row and column #{name}" unless requested_column_index
      
      # Break down the row so there are no colspans. This should provide a
      # 1-1 mapping between the column names and row cells. 
      row_cells_without_colspans = []
      cell_index = 1
      each { |cell| cell.colspan.times {row_cells_without_colspans << cell_index}; cell_index +=1 }
      self[row_cells_without_colspans[requested_column_index]]
    end
  end
  
  
  class IE
    READYSTATE_INTERACTIVE = 3
    @@polling_sleep = 0.05

    def self.version
      @@ie_version ||= begin
        require 'win32/registry'
        ::Win32::Registry::HKEY_LOCAL_MACHINE.open("SOFTWARE\\Microsoft\\Internet Explorer") do |ie_key|
          ie_key.read('Version').last
        end
        # OR: ::WIN32OLE.new("WScript.Shell").RegRead("HKEY_LOCAL_MACHINE\\SOFTWARE\\Microsoft\\Internet Explorer\\Version")
      end
    end

    def self.version_parts
      @@ie_version_parts ||= IE.version.split('.')
    end

    

    def wait(no_sleep=false)
      # don't wait if there's a modal open
      return if @ie.respond_to?('hwnd') && (GetWindow.call(@ie.hwnd, GW_ENABLEDPOPUP)[0] > 0)
      @rexmlDomobject = nil
      @down_load_time = 0.0
      
      start_load_time = Time.now
      begin
        Timeout::timeout(180) {
          begin
            while @ie.busy do; sleep @@polling_sleep; end
            until (@ie.readyState == READYSTATE_COMPLETE) do; sleep @@polling_sleep; end
            until @ie.document do; sleep @@polling_sleep; end
            documents_to_wait_for = [@ie.document]

            rescue WIN32OLERuntimeError # IE window must have been closed
              @down_load_time = Time.now - start_load_time
              return @down_load_time
            end
      
            while doc = documents_to_wait_for.shift
              begin
                until (doc.readyState == "complete") || (doc.readyState == "interactive") do; sleep @@polling_sleep; end
                # don't need this
                #@url_list << doc.location.href unless @url_list.include?(doc.location.href)
                doc.frames.length.times do |n|
                  begin
                    documents_to_wait_for << doc.frames[n.to_s].document
                  rescue WIN32OLERuntimeError, NoMethodError
                  end
                end
              rescue WIN32OLERuntimeError
              end
            end
        }
      rescue Timeout::Error
        puts "Timed out while waiting for browser to load page: #{url}"
        puts @ie.busy.inspect
        puts @ie.readyState.inspect
        puts
        @ie.refresh
      end            
      @down_load_time = Time.now - start_load_time
      run_error_checks
      sleep @pause_after_wait unless no_sleep
      @down_load_time
    end

    def version
      @ie.document.invoke('parentWindow').navigator.appVersion =~ /MSIE\s([\d.]+)/
      $1.to_i
    end

    class Process
      def self.start
        program_files = ENV['ProgramFiles'] || "c:\\Program Files"
        startup_command = "#{program_files}\\Internet Explorer\\iexplore.exe"
        startup_command << " -nomerge" if IE.version_parts.first.to_i == 8
        startup_command << " -extoff" if  ENV['IE_NOEXT'] == 'true'
        process_info = ::Process.create('app_name' => "#{startup_command} about:blank")
        process_id = process_info.process_id
        new process_id
      end
    end
    
    def window
      ie.Document.parentWindow
    end
    
    def goto_no_wait(url)
      ie.navigate(url)
      return @down_load_time
    end
  end
  
  # There's a case where a select list fires a popup so we needed to make
  # sure the control didn't block so we could handle the popup
  class SelectList 
    # We need this for handling modal javascript popups, otherwise the 
    # threads spawned will block and not allow autoit to do it's thing
    def select_no_wait(value)
      assert_exists
      assert_enabled
      object = "#{self.class}.new(self, :unique_number, #{self.unique_number})"
      @page_container.eval_in_spawned_process(object + ".select('#{value}')")
    end
    
    def select(item)
      case item
        when Array
        item.each { |i| select_item_in_select_list(:text, i) }
      else
        select_item_in_select_list(:text, item)
      end
    end
    
    def select_item_in_select_list(attribute, value)
      assert_exists
      highlight(:set)
      found = false

      value = value.to_s unless [Regexp, String].any? { |e| value.kind_of? e }

      @container.log "Setting box #{@o.name} to #{attribute.inspect} => #{value.inspect}"
      @o.each do |option| # items in the list
        if value.matches(option.invoke(attribute.to_s))
          if option.selected
            found = true
            break
          else
            option.selected = true
            @o.fireEvent("onChange")
            # This is faster for select list elements that don't trigger reloads
            begin
              @container.wait if @container.document.readystate == 'loading'
            rescue WIN32OLERuntimeError
              @container.wait
            end
            found = true
            break
          end
        end
      end

      unless found
        raise NoValueFoundException, "No option with #{attribute.inspect} of #{value.inspect} in this select element"
      end
      highlight(:clear)
    end
    
  end
  
  class InputElement
    def value=(x)
      case x
        when Regexp
        set(x)
      else
        set(x.to_s)
      end
    end
  end
  
  class RadioCheckCommon < InputElement
    attr_accessor :how, :what
    
    def radio_value=(x)
      @value = x
    end
    
    # Watir actually fires the OnChange events

    def set_with_onChange
      warn caller.first + "[DEPRECATION] 'set_with_onChange' is deprecated. Use 'set' instead"
      set
    end
    
    def clear_with_onChange
      warn caller.first + "[DEPRECATION] 'clear_with_onChange' is deprecated. Use 'clear' instead"
      clear
    end
    
  end
  
  class Radio

    # Sets (click) the button corresponding to the specified value.
    def value=(x)
      copy = self.dup
      copy.radio_value = x
      copy.set
    end
    
    # Is there a button matching the current specifiers for the provided value?
    def valueIsSet?(x)
      copy = self.dup
      copy.radio_value = x
      copy.exists? && copy.isSet?
    end
    
    # Returns the value that the current button-group is set for.
    def selected_value
      copy = checked_button
      copy.value
    end
    
    private
    # Returns the button matching the current specifiers that is actually checked
    def checked_button
      copy = self.dup
      if copy.how.is_a? Symbol
        copy.how = {copy.how => copy.what}
        copy.what = nil
      end
      copy.how.merge!(:checked => true)
      copy
    end
    
  end
  
  class CheckBox
    def value=(x)
      x ? set : clear
    end
  end

  class Button
    def value=(x)
      click if x
    end
  end
  
  class FileField < InputElement
    def value=(x)
      @container.wait
      filename = File.expand_path(x)
      filename.gsub!("\/","\\")
      filename.gsub!("\\","\\\\")
      set(filename)
    end
  end
  
  # Add support for fieldset elements
  class Fieldset < NonControlElement
    TAG = 'FIELDSET'
  end
  
  class Fieldsets < ElementCollections
    include CommonCollection
    def element_class; Fieldset; end
    private
    def set_show_items
      super
      @show_attributes.delete("name")
      @show_attributes.add("className", 20)
    end
  end
  
  class Frames 
    def initialize(container)
      @container = container
    end
    def each
      frame_count = @container.ie.document.frames.length 
      if frame_count > 0
        1.upto frame_count do |i|
          begin
            frame = @container.frame(:index, i)
            yield frame
          rescue Watir::Exception::UnknownFrameException
            # frame can be already destroyed
          end          
        end
      end
    end
  end
  
  module Container
    def fieldset(how, what)
      return Fieldset.new(self, how, what)
    end
    def fieldsets
      return Fieldsets.new(self)
    end

    def frames
      Frames.new(self)
    end
    
  end
  
  class Frame 
    attr_accessor :o
    def ole_object; @o; end
  end
  
  class Element
    def_wrap_guard :checked
    def_wrap_guard :has_cell
    def has_cell x
      self.cell(:text, x).exists?
    end
    def has_label x
      self.label(:text, x).exists?
    end
    
    def click_if_exists
      click if exists?
    end
    
    def nextsibling
      assert_exists
      result = Element.new(ole_object.nextSibling)
      result.set_container self
      result
    end
    
    def prevsibling
      assert_exists
      result = Element.new(ole_object.previousSibling)
      result.set_container self
      result
    end
    
    # If any parent element isn't visible then we cannot write to the
    # element. The only realiable way to determine this is to iterate
    # up the DOM element tree checking every element to make sure it's
    # visible.
    def visible?
      # Now iterate up the DOM element tree and return false if any
      # parent element isn't visible or is disabled.
      object = document
      while object
        if object.style.invoke('visibility') =~ /^hidden$/i
          return false
        end
        if object.style.invoke('display') =~ /^none$/i
          return false
        end
        if object.invoke('isDisabled')
          return false
        end
        object = object.parentElement
      end
      
      return true
    end
    
    
  end # class Element
end

class WinClicker
  
  # Change window match so it's an exact title (otherwise we'll set focus to every window when checking for session expiration
  def getWindowHandle_byexacttitle(title, winclass = "" )
    enum_windows = @User32['EnumWindows', 'IPL']
    get_class_name = @User32['GetClassName', 'ILpI']
    get_caption_length = @User32['GetWindowTextLengthA' ,'LI' ]    # format here - return value type (Long) followed by parameter types - int in this case -      see http://www.ruby-lang.org/cgi-bin/cvsweb.cgi/~checkout~/ruby/ext/dl/doc/dl.txt?
    get_caption = @User32['GetWindowTextA', 'iLsL' ] 
    
    len = 32
    buff = " " * len
    classMatch = false
    
    bContinueEnum = -1  # Windows "true" to continue enum_windows.
    found_hwnd = -1
    sleep 1
    enum_windows_proc = DL.callback('ILL') {|hwnd,lparam|
      #sleep 0.05
      r,rs = get_class_name.call(hwnd, buff, buff.size)
      
      if winclass != "" then
        if /#{winclass}/ =~ rs[1].to_s
          classMatch = true
        end
      else
        classMatch = true 
      end
      
      if classMatch == true
        textLength, a = get_caption_length.call(hwnd)
        captionBuffer = " " * (textLength+1)
        t ,  textCaption  = get_caption.call(hwnd, captionBuffer  , textLength+1)    
        if title == textCaption[1].to_s
          found_hwnd = hwnd
          bContinueEnum = 0 # False, discontinue enum_windows
        end
        bContinueEnum
      else
        bContinueEnum
      end
    }
    enum_windows.call(enum_windows_proc, 0)
    DL.remove_callback(enum_windows_proc)
    return found_hwnd
  end
end



