#!/usr/bin/env ruby

# Regression test for mod_zip issue #108, "Excessive memory usage".
# https://github.com/evanmiller/mod_zip/issues/108
#
#
# Usage:
#   ruby test/performance/modzip_memory_test.rb
#
# Tunable through the environment:
#   MODZIP_FILE_COUNT           number of files in the archive (default 10000)
#   MODZIP_FILE_SIZE            bytes per file (default 1024)
#   MODZIP_MAX_PEAK_GROWTH_KB   fail above this peak growth (default 102400, i.e. 100 MB)
#   MODZIP_ROOT                 working directory (default /tmp/modzip-memory)
#   MODZIP_KEEP                 set to keep the generated files behind for inspection

require 'net/http'
require 'fileutils'
require 'zlib'

class ModzipMemoryTest
  FILE_COUNT = Integer(ENV['MODZIP_FILE_COUNT'] || 10_000)
  FILE_SIZE = Integer(ENV['MODZIP_FILE_SIZE'] || 1024)
  MAX_PEAK_GROWTH_KB = Integer(ENV['MODZIP_MAX_PEAK_GROWTH_KB'] || 100 * 1024)
  ROOT = ENV['MODZIP_ROOT'] || '/tmp/modzip-memory'

  HOST = '127.0.0.1'
  PORT = 8090
  CONF = 'modzip-memory-test.conf'
  LOCAL_FILE_HEADER = "PK\x03\x04".b
  # End of central directory, plain and ZIP64. Without one of these no unzip tool will open the
  # archive: running out of file descriptors mid-stream produces exactly that, a 200 response whose
  # body stops before the central directory is written.
  END_OF_CENTRAL_DIR = "PK\x05\x06".b
  END_OF_CENTRAL_DIR64 = "PK\x06\x06".b

  def initialize
    @nginx = ENV['NGINX_BIN'] || `which nginx`.strip
    abort 'nginx binary not found, set NGINX_BIN' if @nginx.empty?
    @conf_source = File.expand_path("../#{CONF}", __dir__)
    @failures = []
  end

  def run
    banner
    prepare_files
    write_manifests

    measure('without CRC-32 (the condition reported in #108)', 'manifest-nocrc.txt')
    measure('with CRC-32 (what KurierPlikow sends)', 'manifest-crc.txt')

    cleanup unless ENV['MODZIP_KEEP']
    report
  end

  private

  def banner
    puts '--- mod_zip memory test, issue #108 ---'
    puts format('Archive: %d files x %d B = %.1f MB of payload',
                FILE_COUNT, FILE_SIZE, FILE_COUNT * FILE_SIZE / 1024.0 / 1024)
    puts format('Budget:  %d KB of peak worker growth (%.1f KB per file)',
                MAX_PEAK_GROWTH_KB, MAX_PEAK_GROWTH_KB.to_f / FILE_COUNT)
    puts
  end

  # Deterministic printable content. Kept free of the "PK\x03\x04" byte sequence so that counting
  # local file headers in the response cannot be fooled by file payloads.
  def content_for(index)
    head = format("modzip memory test file %06d\n", index)
    filler = 'abcdefghijklmnopqrstuvwxyz0123456789 '
    (head + filler * FILE_SIZE)[0, FILE_SIZE]
  end

  def file_name(index)
    format('f%06d.txt', index)
  end

  def prepare_files
    FileUtils.rm_rf(ROOT)
    %w[files manifests client_body_temp proxy_temp].each { |d| FileUtils.mkdir_p(File.join(ROOT, d)) }
    FileUtils.cp(@conf_source, File.join(ROOT, CONF))

    print "Creating #{FILE_COUNT} files in #{ROOT}/files ... "
    @crcs = Array.new(FILE_COUNT)
    FILE_COUNT.times do |i|
      body = content_for(i)
      @crcs[i] = Zlib.crc32(body)
      File.binwrite(File.join(ROOT, 'files', file_name(i)), body)
    end
    puts 'done'
  end

  def write_manifests
    nocrc = +''
    crc = +''
    FILE_COUNT.times do |i|
      name = file_name(i)
      nocrc << format("- %d /files/%s %s\n", FILE_SIZE, name, name)
      crc << format("%08x %d /files/%s %s\n", @crcs[i], FILE_SIZE, name, name)
    end
    File.write(File.join(ROOT, 'manifests', 'manifest-nocrc.txt'), nocrc)
    File.write(File.join(ROOT, 'manifests', 'manifest-crc.txt'), crc)
    # Single entry archive, served before every measurement so that nginx's one-off allocations for
    # the first request land in the baseline instead of being charged to the file count.
    File.write(File.join(ROOT, 'manifests', 'manifest-warmup.txt'),
               format("%08x %d /files/%s %s\n", @crcs[0], FILE_SIZE, file_name(0), file_name(0)))
    puts format("Manifests written (%d KB without CRC, %d KB with CRC)\n\n",
                nocrc.bytesize / 1024, crc.bytesize / 1024)
  end

  def measure(label, manifest)
    puts "== #{label}"
    start_nginx
    begin
      worker = worker_pid
      download('manifest-warmup.txt')
      baseline_kb = vm_hwm_kb(worker)
      peak_fds = open_fds(worker)

      # Unlike RSS, the kernel keeps no high-water mark for open descriptors, so this has to be
      # sampled. Sample hard: a 10000 file archive is assembled in a fraction of a second, and a
      # coarse interval will simply miss the peak and report a reassuring number.
      sampler = Thread.new do
        loop do
          fds = open_fds(worker)
          peak_fds = fds if fds > peak_fds
          sleep 0.002
        end
      end

      entries, bytes, elapsed, status, complete = download(manifest)
      sampler.kill
      peak_kb = vm_hwm_kb(worker)
      growth_kb = peak_kb - baseline_kb

      puts format('  HTTP status      %s', status)
      puts format('  archive          %.1f MB in %.1fs', bytes / 1024.0 / 1024, elapsed)
      puts format('  entries found    %d of %d expected', entries, FILE_COUNT)
      puts format('  central dir      %s', complete ? 'present, archive is openable' : 'MISSING, archive will not open')
      puts format('  worker peak RSS  %d KB baseline -> %d KB peak, growth %d KB', baseline_kb, peak_kb, growth_kb)
      puts format('  per file         %.2f KB', growth_kb.to_f / FILE_COUNT)
      puts format('  peak open fds    %d', peak_fds)

      check(status == '200', "#{label}: expected HTTP 200, got #{status}")
      check(entries == FILE_COUNT, "#{label}: archive has #{entries} entries, expected #{FILE_COUNT}")
      check(complete, "#{label}: archive has no end of central directory record, no unzip tool will open it")
      check(growth_kb <= MAX_PEAK_GROWTH_KB,
            format('%s: worker grew by %d KB (%.2f KB per file), budget is %d KB',
                   label, growth_kb, growth_kb.to_f / FILE_COUNT, MAX_PEAK_GROWTH_KB))
    rescue StandardError => e
      check(false, "#{label}: #{e.class}: #{e.message}")
      dump_error_log
    ensure
      stop_nginx
      puts
    end
  end

  # Streams the response so that the client side stays flat too, and counts ZIP local file headers
  # as they go past. The 3 byte carry stops a header straddling two chunks from being missed; it
  # cannot cause a double count because a 4 byte signature does not fit in 3 carried bytes.
  def download(manifest)
    entries = 0
    bytes = 0
    complete = false
    status = nil
    started = Time.now
    Net::HTTP.start(HOST, PORT, read_timeout: 600) do |http|
      http.request(Net::HTTP::Get.new("/zip/#{manifest}")) do |response|
        status = response.code
        break unless status == '200'

        carry = ''.b
        response.read_body do |chunk|
          bytes += chunk.bytesize
          window = carry + chunk.b
          entries += window.scan(LOCAL_FILE_HEADER).size
          complete ||= window.include?(END_OF_CENTRAL_DIR) || window.include?(END_OF_CENTRAL_DIR64)
          carry = window[-3, 3] || window
        end
      end
    end
    [entries, bytes, Time.now - started, status, complete]
  end

  def start_nginx
    FileUtils.rm_f(Dir[File.join(ROOT, 'modzip-memory-error.log')])
    unless system(@nginx, '-p', ROOT, '-c', CONF)
      dump_error_log
      abort 'nginx failed to start'
    end
    wait_for_port
  end

  def stop_nginx
    system(@nginx, '-p', ROOT, '-c', CONF, '-s', 'stop', out: File::NULL, err: File::NULL)
    30.times do
      break unless File.exist?(File.join(ROOT, 'modzip-memory.pid'))

      sleep 0.1
    end
  end

  def wait_for_port
    50.times do
      begin
        TCPSocket.new(HOST, PORT).close
        return
      rescue SystemCallError
        sleep 0.1
      end
    end
    abort "nginx did not start listening on #{HOST}:#{PORT}"
  end

  def master_pid
    File.read(File.join(ROOT, 'modzip-memory.pid')).strip.to_i
  end

  def worker_pid
    master = master_pid
    20.times do
      pids = Dir['/proc/[0-9]*/status'].filter_map do |status|
        text = File.read(status) rescue next
        next unless text.include?('Name:\tnginx') || text[/\AName:\s+nginx$/]
        next unless text[/^PPid:\s+(\d+)$/, 1].to_i == master

        File.basename(File.dirname(status)).to_i
      end
      return pids.first if pids.any?

      sleep 0.1
    end
    abort "no nginx worker found under master #{master}"
  end

  def vm_hwm_kb(pid)
    File.read("/proc/#{pid}/status")[/^VmHWM:\s+(\d+) kB$/, 1].to_i
  rescue Errno::ENOENT
    0
  end

  def open_fds(pid)
    Dir.children("/proc/#{pid}/fd").size
  rescue SystemCallError
    0
  end

  def dump_error_log
    log = File.join(ROOT, 'modzip-memory-error.log')
    return unless File.exist?(log)

    puts '  --- nginx error log (tail) ---'
    File.readlines(log).last(15).each { |line| puts "  #{line.rstrip}" }
  end

  def check(condition, message)
    @failures << message unless condition
  end

  def cleanup
    FileUtils.rm_rf(ROOT)
  end

  def report
    if @failures.empty?
      puts 'mod_zip memory test: PASSED'
      exit 0
    end
    puts 'mod_zip memory test: FAILED'
    @failures.each { |f| puts "  - #{f}" }
    exit 1
  end
end

ModzipMemoryTest.new.run if $PROGRAM_NAME == __FILE__
