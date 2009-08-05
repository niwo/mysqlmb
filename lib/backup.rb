module MySqlMb
  class Backup
    include Comparable
    
    attr_reader :db_name, :day, :path

    def initialize(db_name, date, path)
      @db_name = db_name
      @day = day
      @path = path
    end
    
    def to_s
      @db_name
    end

    def <=>(other)
      @path <=> other.path
    end

    def file_name
      File.basename(@path)
    end

    def extname
      File.extname(@path)
    end

    def dirname
      File.dirname(@path)
    end

    def path_without_extension
      File.join(dirname(), File.basename(@path, extname())) 
    end
  end
end
