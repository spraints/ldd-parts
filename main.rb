require "nokogiri"
require "pp"
require "zip"

def main
  db = DB.new
  ARGV.each do |path|
    list_parts db, path
  end
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
#        $stderr.puts xml
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
    if id = info[:part_design_id]
      material = info[:part_materials]
      "#{primitive_name(id)} (#{id}) #{material_name(material.split(",").first)} (#{material})"
    else
      info.inspect
    end
  end

  private

  def primitive_name(id)
    primitive_names[id]
  end

  def material_name(id)
    material_names[id]
  end

  def primitive_names
    @primitive_names ||= Hash.new { |h,k| h[k] = get_primitive_name(k) }
  end

  def material_names
    @material_names ||= read_materials
  end

  def read_materials
    materials = Hash.new("unknown")
    File.open "materials.loc", "wb" do |f|
      state = :init
      id = nil
      read("/MaterialNames/EN/localizedStrings.loc").split("\0").each do |str|
#        $stderr.puts [state, id, str].inspect
        case state
        when :init
          state = :name
        when :name
          id = str.sub("Material", "")
          state = :val
        when :val
          materials[id] = str
          state = :name
        end
      end
    end
    materials
  end

  def get_primitive_name(id)
    xml = Nokogiri::XML(read("/Primitives/#{id}.xml"))
    infos = {}
    xml.xpath("/LEGOPrimitive/Annotations/Annotation").each do |e|
      e.attributes.each do |name, attr|
        infos[name] = attr.value
      end
    end
    # ["aliases", "designname", "maingroupid", "maingroupname", "platformid", "platformname", "version"]
    infos["designname"]
  end

  def read(db_file)
    info = file_list[db_file]
    f.seek(info[:offset])
    f.read(info[:length])
  end

  def file_list
    @file_list ||= FileList.new(f)
  end

  def f
    @f ||= File.open(ldd_db_path, "rb")
  end

  def ldd_db_path
    [ENV["LDD_DB_PATH"], "#{ENV["HOME"]}/Library/Application Support/LEGO Company/LEGO Digital Designer/db.lif", "db.lif"].each do |path|
      if path && File.exist?(path)
        return path
      end
    end
    raise "Couldn't find db.lif!"
  end
end

class FileList
  def initialize(f)
    @f = f
  end

  attr_reader :f

  def [](name)
    _file_list[name]
  end

  private

  def _file_list
    @file_list ||= read_file_list
  end

  def read_file_list
    f.seek 0
    tag = f.read(4)
    tag == "LIFF" or raise "Expected LIFF, got #{tag.inspect}"

    packed_files_offset = [84]
    file_list = {}

    recurse "", uint32(f, 72) + 64, f, packed_files_offset, file_list

    file_list
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

  def recurse(prefix, offset, f, packed_files_offset, file_list)
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
        packed_files_offset[0] += 20
        offset = recurse(prefix + entry_name, offset, f, packed_files_offset, file_list)
      when 2
        packed_files_offset[0] += 20
        file_offset = packed_files_offset[0]
        file_size = uint32(f, offset) - 20
        offset += 24
        packed_files_offset[0] += file_size
        file_list[prefix + entry_name] = {:offset => file_offset, :length => file_size}
      end
    end

    offset
  end
end

main
