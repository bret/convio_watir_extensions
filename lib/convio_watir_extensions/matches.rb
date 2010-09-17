class Array
  def matches(x)
    self.each do |item|
      return self.index(item) if x.matches(item)
    end
    return false
  end
end

class TrueClass
  def matches(x)
    self.== x
  end
end

class FalseClass
  def matches(x)
    self.== x
  end
end

# This is a workaround for a failure I'm seeing in getting
# ole to work with a checkbox. Look later to find the right fix
class WIN32OLE
  def matches(x)
    return self.outerHTML == x.outerHTML
  end
end
