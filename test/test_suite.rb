require 'rubygems'
gem 'test-unit'
require 'test/unit'

class TestSuite < Test::Unit::TestCase
  #empty class to fool IDE
end

$VERBOSE = false
tests = Dir[File.expand_path("#{File.dirname(__FILE__)}/*_test.rb")]
tests.each do |file|
  require(file)
end