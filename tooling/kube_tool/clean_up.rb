require 'fileutils'

class CleanUp
  def self.all(files)
    files.each do |x|
      if File.exist?(x)
        FileUtils.rm_f(x)
      end
    end
  end

  def self.remove_yaml
    puts "Cleaning up *.yaml | *.eyaml files"
    FileUtils.rm Dir.glob('*.yaml')
    FileUtils.rm Dir.glob('*.eyaml')
  end

  def self.remove_files
    puts "Cleaning up files"
    FileUtils.rm Dir.glob('*.csr')
    FileUtils.rm Dir.glob('*.json')
    FileUtils.rm Dir.glob('*.pem')
    FileUtils.rm Dir.glob('*.log')
    FileUtils.rm('discovery_token_hash')
  end

  def self.clean_yaml
    puts "Cleaning up yaml"
    File.write("kubernetes.yaml",File.open("kubernetes.yaml",&:read).gsub(/^---$/,""))
    Dir.glob('*.eyaml') do |eyaml|
      File.write(eyaml,self.fix_multiline_eyaml(eyaml))
    end
  end

  def self.fix_multiline_eyaml(filename)
    lines = ['---']
    File.foreach(filename) do |line|
      line.gsub!(/^---$/,'')
      #line.gsub!(/^---(\s+\{\})?$/,'')
      # replace |- by >
      line.gsub!(/(kubernetes::.*:\s+)\|\-/,'\1>')
      lines << line
    end
    lines.join
  end

end
