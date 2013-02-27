def command_exists?(command)
  %x(type #{command} > /dev/null 2>&1 )
 $?.exitstatus == 0
end

requirements = %(
  brew install ghc --64bit --use-llvm
  brew install haskell-platform --64bit --use-llvm
  cd my_migrate
  sh install 
)

unless File.exists?(".requirements.met")

  unless command_exists?('runghc') 
    puts "Looks like Haskell is not installed!"
    puts "Fix like so:"
    puts requirements
    exit
  end

  unless command_exists?('cabal')
    puts "You need to run 'sh install' in project root, not all requirements are met."
    puts requirements
    exit
  end

  %x(touch .requirements.met)
end
