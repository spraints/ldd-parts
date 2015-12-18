def main
  ldd_db = read_ldd_db
end

def read_ldd_db
  File.open "db.lif", "rb" do |f|
    (f.read(4) == "LIFF") or raise "Expected LIFF, got #{tag.inspect}"

    pfo = [84]
    fl = []

    ldd_recurse "", uint32(f, 72) + 64, f, pfo, fl

    puts fl.map(&:first)
  end
end

def uint32(f, n = nil)
  n && f.seek(n)
  encoded = f.read(4)
  encoded.unpack("L>").first
end

def uint16(f, n = nil)
  n && f.seek(n)
  encoded = f.read(2)
  encoded.unpack("S>").first
end

def ldd_recurse(prefix, offset, f, pfo, fl)
  if prefix == ""
    offset += 36
  else
    offset += 4
  end

  1.upto(uint32(f, offset)) do
    offset += 4
    entry_type = uint16(f, offset)
    offset += 6

    entry_name = "/"
    loop do
      f.seek offset + 1
      c = f.read 1
      break if c == "\x00"
      entry_name << c
      offset += 2
    end
    offset += 6

    case entry_type
    when 1
      pfo[0] += 20
      offset = ldd_recurse(prefix + entry_name, offset, f, pfo, fl)
    when 2
      pfo[0] += 20
      file_offset = pfo[0]
      file_size = uint32(f, offset) - 20
      offset += 24
      pfo[0] += file_size
      fl.push [prefix + entry_name, file_offset, file_size]
    end
  end

  offset
end

main
