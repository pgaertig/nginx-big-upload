require 'power_assert'
require 'benchmark'

class PerformanceTest

  attr_accessor :http

  def run
    @http = Net::HTTP.new 'localhost', 8088
    @upload_path = "/tmp"
    @body512k = "Performant" * 51 * 1024 # ~512KB chunk
    @body2mb = "Performant" * 200 * 1024 # ~2mb chunk

    puts "--- Unit tests successful, now starting performance test..."

    #Warmup
    run_cycle('perfwrm1', 'http://localhost:8088/upload/perf-bu', 20, @body512k)
    run_cycle('perfwrm2', 'http://localhost:8088/upload/perf-bu-crc', 20, @body512k)
    run_cycle('perfwrm3', 'http://localhost:8088/upload/perf-bu-crc-server', 20, @body512k)
    run_cycle('perfwrm4', 'http://localhost:8088/upload/perf-bu-sha1', 20, @body512k)
    run_cycle('perfwrm5', 'http://localhost:8088/upload/perf-bu-full', 20, @body512k)

    puts "Legend: [total], [files]x[chunks]x[chunk size], [options] (real time)"

    report("524MB, 10x100x512K") { 10.times {
       run_cycle('perfbu1', 'http://localhost:8088/upload/perf-bu', 100, @body512k)
    }}

    report("524MB, 10x100x512K, CRC32") { 10.times {
      run_cycle('perfbu2', 'http://localhost:8088/upload/perf-bu-crc', 100, @body512k)
    }}

    report("524MB, 10x100x512K, CRC32s") { 10.times {
      run_cycle('perfbu3', 'http://localhost:8088/upload/perf-bu-crc-server', 100, @body512k)
    }}

    report("524MB, 10x100x512K, SHA1") { 10.times {
      run_cycle('perfbu4', 'http://localhost:8088/upload/perf-bu-sha1', 100, @body512k)
    }}

    report("524MB, 10x100x512K, SHA1, CRC32s") { 10.times {
      run_cycle('perfbu5', 'http://localhost:8088/upload/perf-bu-full', 100, @body512k)
    }}

    report("  2GB, 10x400x512K") {10.times {
       run_cycle('perfbu6', 'http://localhost:8088/upload/perf-bu', 400, @body512k)
    }}

    report("  1GB, 10x50x2MB") { 10.times {
      run_cycle('perfbu7', 'http://localhost:8088/upload/perf-bu', 50, @body2mb)
    }}

    puts "--- End of performance test ---"
  end

  def report label, &block
    printf " * %-35s", label
    printf "(%.3fs)\n", Benchmark.realtime(&block)
  end

  def run_cycle(id, uri, chunks_no, chunk_data)
    file = "/tmp/#{id}"
    File.delete(file) if File.exists?(file)
    req = Net::HTTP::Post.new uri
    req.body = chunk_data
    req['content-type'] = 'application/octet-stream'
    req['Content-Disposition'] = 'attachment; filename="somename.dat"'
    req['session-id'] = id
    chunk_size = req.body.size
    total_size = chunks_no * chunk_size
    offset = 0
    for chunk in 1..chunks_no
      req['content-range'] = "bytes #{offset}-#{offset+chunk_size - 1}/#{total_size}"
      res = http.request(req)
      if chunk == chunks_no
        "202" == res.code || raise("Expected 202")
        res.body =~ /path/ || raise("No 'path' in body: #{res.body}")
      else
        "201" == res.code || raise("Expected code 201: #{res.body}")
      end
      offset += chunk_size
    end

    File.exists?(file) || raise("Uploaded file does not exists: #{file}")
    total_size == File.size(file) || raise("Uploaded size differs: #{total_size} vs #{File.size(file)}")
    1 == File.delete(file) || raise("Can't delete file: #{file}")
    crcfile = file + '.crc32'
    shafile = file + '.shactx'
    File.exists?(crcfile) && File.delete(crcfile)
    File.exists?(shafile) && File.delete(shafile)
  end


end