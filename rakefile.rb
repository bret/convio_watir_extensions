require 'rubygems'
require 'rake/rdoctask'
require 'spec/rake/spectask'
require 'rake/gempackagetask'

require 'lib/convio_watir_extensions/version'

task :default => [:gem]

# Specification for gem creation
spec = Gem::Specification.new do |s|
    s.name               = ConvioWatirExtensions::VERSION::NAME
    s.version            = ConvioWatirExtensions::VERSION::STRING
    s.files              = FileList['lib/**/*'].to_a
    s.author             = 'Hugh McGowan'
    s.email              = 'hmcgowan@convio.com' 
    s.has_rdoc           = true 
    s.homepage           = 'http://twiki.convio.com/twiki/bin/view/Engineering/RubyWatir'
    s.rubyforge_project  = 'none'
    s.summary            = ConvioWatirExtensions::VERSION::SUMMARY
    s.description        = <<-EOF
        These are extensions to the existing watir libraries
    EOF
    ConvioWatirExtensions::DEPENDENCIES.each do |gem|
      s.add_dependency gem
    end
end

Rake::RDocTask.new(:rdoc) do |rd|
  rd.rdoc_files.include("lib/**/*.rb")
  rd.options << "--all"
end
 
Spec::Rake::SpecTask.new do |t|
  t.rcov = true
  t.spec_files = FileList['spec/**/*_spec.rb']
  t.spec_opts << '-fs'
end

package = Rake::GemPackageTask.new(spec) {}
gem = "ruby #{Config::CONFIG['bindir']}\\gem"

desc 'Create the gem'
task :install => :gem do 
  sh "#{gem} install --both --no-rdoc --no-ri pkg\\#{package.gem_file} --source http://qalin.corp.convio.com:8808"
end

desc "deploy the gem to the gem server; must be run on on qalin"
task :deploy => :gem do
  sh "#{gem} install --local -i c:/gemserver/ruby/gems --no-ri pkg\\#{package.gem_file}"
end

