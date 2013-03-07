module MyMigrate
  class Actions
  
    include CustomActions
    attr_accessor :list
    def initialize
      @config = MyMigrate.config
      @list = @config.actions_set
      #@config.dry_run = ENV['DRY_RUN'] == 'false' ? false : true
    end
  

   def list
      # ORDER MATTERS, perform overrides here
      @list
   end 
  
   def start_at(name,go=false)
     list.each do |ea|
       go = true if name == ea
       _run(self.send(ea.to_sym),ea) if go
      end
    end

    def run_and_skip(names) 
      list.each do |ea|
        unless names.include?(ea.to_sym) || names.include?(ea.to_s)
          _run(self.send(ea.to_sym),ea)
        end
      end
    end

    def run_until(name)
      list.each do |ea|
        if name == ea
          break
        end
        _run(self.send(ea.to_sym),ea) 
      end
    end    
    def run_all
      list.each do |ea|
        _run(self.send(ea.to_sym), ea)
      end
    end

    def dump_mysql_ddl
      %(#{mysqldump_conn} -d > ddl/mysql.ddl)
    end  

    def convert_mysql_ddl_to_postgres
      %(cat ddl/mysql-cleaned.ddl | runghc lib/parse.hs > ddl/postgres.ddl)
    end

    def fix_nulls
      %(sed -i 'bak' 's/\\\\N/#{@config.source.replace_null_string}/g' dumps/*.txt)
    end

    def split_indexes_from_postgres
      %(cat ddl/postgres.ddl | grep 'create index' > ddl/postgres-idx.ddl)
    end

    def split_ddl_from_postgres
      %(cat ddl/postgres.ddl | grep -v 'create index' > ddl/postgres-noidx.ddl)
    end

    
    # parallel dump
    def dump_mysql
      cmds = []
      this_command = %(cd dumps;)
      this_command += %( #{mysql_conn} -B -e 'SHOW TABLES' | sed -e '$!N; s/Tables_in_.*//' | )
      this_command += %( parallel -j+0 "#{mysqldump_conn} --compatible=postgresql -T './' --fields-terminated-by='#{@config.source.fields_terminated_by}' --fields-enclosed-by='#{@config.source.fields_enclosed_by}' --tables {}" )
      #cmds << %(cd dumps; #{mysqldump_conn} --compatible=postgresql -T './' --fields-terminated-by='#{@config.source.fields_terminated_by}' --fields-enclosed-by='#{@config.source.fields_enclosed_by}';)
      this_command
    end

    def load_postgres_ddl
      %( #{psql_conn}  < ddl/postgres-noidx.ddl)
    end

    def drop_create_target
      drop = ask "Do you want to drop and create target?[y/n]"
      if drop.downcase == 'y'
        %(dropdb #{@config.target.database};createdb #{@config.target.database})
      else
        %(echo 'Skipping drop and create of target DB')
      end
    end

    def load_csvs
      cmds = []
      path = File.join(Dir.pwd,'dumps')
      csvs = Dir["#{path}/*.txt"]
      csvs.each do |csv|
       puts "importing #{csv}..."
       cmds << %(#{psql_conn} -c "COPY #{File.basename(csv,'.txt')}  from '#{csv}' delimiter as '#{@config.source.fields_terminated_by}' NULL '#{@config.source.replace_null_string}' csv QUOTE as '#{@config.source.fields_enclosed_by}';")
      end
      cmds
    end
    
    def load_postgres_indexes
      %(#{psql_conn} < ddl/postgres-idx.ddl)
    end
    
    
    # for direct use in console
    def run(cmd)
      _run(self.send(cmd.to_sym),cmd)
      nil
    end
    def _run(cmds,name)
      if cmds.instance_of? Array
        cmds.each do |cmd|
          run_one cmd,name
        end
      else
        run_one cmds,name
      end
    end

    def run_one(cmd,name)
      puts "Running command: #{name}"
      puts "#{(cmd)}" 
      unless @config.dry_run
        puts "*"*10
        %x(#{cmd})
         if @config.stop_on_error $?.exitstatus != 0
          puts "There was an error running the command. Please check your databases and configuration."
          exit
        end
      else
        puts "-"*10
      end
      puts ""
    end

    protected
    
    def mysql_conn
      if @config.source.password
        %(mysql -u#{@config.source.username} -p#{@config.source.password} -h #{@config.source.hostname} #{@config.source.database} )
      else
        %(mysql -u#{@config.source.username} -h #{@config.source.hostname} #{@config.source.database} )
      end

    end

    def mysqldump_conn
      if @config.source.password
        %(mysqldump -u#{@config.source.username} -p#{@config.source.password} -h #{@config.source.hostname} #{@config.source.database} )
      else
        %(mysqldump -u#{@config.source.username} -h #{@config.source.hostname} #{@config.source.database} )
      end
    end

    def psql_conn
      %(PGPASSWORD=#{@config.target.password} psql #{@config.target.database} -h #{@config.target.hostname} -U #{@config.target.username} )
    end
  

  end
end
