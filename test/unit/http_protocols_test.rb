#!/usr/bin/env ruby

require './test_helper'

# Uploads only work over HTTP/1.1. ngx.req.socket() refuses to wrap an HTTP/2 or HTTP/3 downstream
# connection and raises a Lua error, so the request ends as 500 and the reason lands in the error log.
#
# The limit is not in this project, lua-nginx-module rejects both outright in
# ngx_http_lua_req_socket(), still present in v0.10.31:
# https://github.com/openresty/lua-nginx-module/blob/v0.10.31/src/ngx_http_lua_socket_tcp.c#L5355-L5365
class HttpProtocolsTest < Test::Unit::TestCase

  ERROR_LOG = '/tmp/nbu-proto-error.log'
  HTTP2_URL = 'http://localhost:8833/upload/resumable'
  HTTP3_URL = 'https://localhost:8834/upload/resumable'

  # Hopefully someday these tests will fail
  def test_httpv2_not_supported
    status = version = nil
    logged = capture_error_log { status, version = upload('--http2-prior-knowledge', HTTP2_URL) }

    assert_equal '2', version, 'curl did not negotiate HTTP/2'
    assert status.to_i >= 400, "expected an error status over HTTP/2, got #{status}"
    assert_match(/http v2 not supported yet/, logged)
  end

  def test_httpv3_not_supported
    omit 'curl on this system was built without HTTP/3' unless curl_supports_http3?

    status = version = nil
    logged = capture_error_log { status, version = upload('--http3-only -k', HTTP3_URL) }

    assert_equal '3', version, 'curl did not negotiate HTTP/3'
    assert status.to_i >= 400, "expected an error status over HTTP/3, got #{status}"
    assert_match(/http v3 not supported yet/, logged)
  end

  private

  def curl_supports_http3?
    `curl -V`.include?('HTTP3')
  end

  def upload(curl_opts, url)
    `curl -s -o /dev/null -w '%{http_code} %{http_version}' #{curl_opts} -X PUT -H 'session-id: 12345' --data-binary 'Part1' #{url}`.split
  end

  def capture_error_log
    offset = File.size?(ERROR_LOG) || 0
    yield
    20.times do
      added = read_from(offset)
      return added unless added.empty?

      sleep 0.1
    end
    read_from(offset)
  end

  def read_from(offset)
    return '' unless File.exist?(ERROR_LOG)

    File.open(ERROR_LOG) { |f| f.seek(offset); f.read.to_s }
  end
end
