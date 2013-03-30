require 'net/http'
require 'test/unit'

class Test::Unit::TestCase


  #Utility assert functions
  def assert_new_file(id, content, &block)
    assert_not_empty id
    file = File.join @upload_path, id
    File.delete file if File.exists? file
    assert ! File.exists?(file)
    yield
    assert_file_content(id, content)
    File.delete file
  end

  def assert_file_content(id, content)
    assert_not_empty id
    file = File.join @upload_path, id
    assert File.exists?(file)
    fcontent = File.read(file)
    assert_not_nil fcontent
    assert_equal content, fcontent
  end

  def assert_no_file(id, &block)
    assert_not_empty id
    file = File.join @upload_path, id
    File.delete file if File.exists? file
    assert ! File.exists?(file)
    yield
    assert ! File.exists?(file)
  end
end