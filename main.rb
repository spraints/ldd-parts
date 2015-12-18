require "nokogiri"
require "pp"
require "zip"

def main
  db = DB.new
  ARGV.each do |path|
    list_parts db, path
  end
#  ldd_db = read_ldd_db
end

def list_parts(db, lxf)
  parts = count_parts(lxf)
  parts.each do |info, count|
    puts "#{count} #{db.describe(info)}"
  end
end

def count_parts(lxf)
  parts = Hash.new(0)
  Zip::File.open(lxf) do |zip|
    zip.each do |entry|
      if entry.name =~ /\.lxfml/i
        xml = Nokogiri::XML(zip.get_input_stream(entry.name).read)
        xml.xpath("/LXFML/Bricks/Brick").each do |brick|
          info = {}
          info[:brick_design_id] = brick["designID"]
          info[:brick_item_nos] = brick["itemNos"]
          part = brick.xpath("Part").first
          info[:part_design_id] = part["designID"]
          info[:part_materials] = part["materials"]
          parts[info] += 1
        end
      end
    end
  end
  parts
end

class DB
  def describe(info)
  end

  def file_list
    @file_list ||= FileList.new(f)
  end

  private

  def f
    @f ||= File.open("db.lif", "rb")
  end
end

class FileList
  def initialize(f)
    @f = f
  end

  attr_reader :f

  def names
    file_list.keys
  end
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
