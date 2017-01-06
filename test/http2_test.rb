#!/usr/bin/env ruby

require './test_helper'
require 'net-http2'

# Test that HTTP2 is still not supported by Nginx+Lua

class Http2Test < Test::Unit::TestCase

  def setup
    @http2 = NetHttp2::Client.new 'http://localhost:8833'
    @path = '/upload/resumable'
  end

  # Hopefully someday this test will fail
  def test_httpv2_not_supported
    assert @http2
    assert_raise HTTP2::Error::ProtocolError do
      res = @http2.call(:put, @path, { body: "Part1", headers: { 'session-id' => '12345' }})
    end
  end
end
