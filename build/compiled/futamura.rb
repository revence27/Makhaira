#!  /usr/bin/env ruby

require 'hpricot'

class String
  def to_java
    self.inspect
  end
end

class NilClass
  def to_java
    'null'
  end
end

class Fixnum
  def to_java
    self
  end
end

class Array
  def to_java
    '{%s}' % [self.as_java]
  end

  def as_java
    self.map {|x| x.to_java}.join(', ')
  end
end

class Indexed
  def [] x
    if block_given? then
      yield self.contents[x]
    else
      self.contents[x]
    end
  end
end

class Chapter
  attr_reader :verses
  alias contents verses
  def initialize
    @verses = yield
  end
end

class Book
  attr_reader :chapters, :name
  alias contents chapters
  def initialize name
    @name     = name
    @chapters = yield
  end
end

class Bible
  attr_reader :books, :name
  alias contents books
  def initialize nom
    @name  = nom
    @books = yield
  end

  def to_java
    self.as_java
  end

  def as_java
    @books.map do |book|
      book.chapters.map do |chp|
        chp.verses.map {|v| v.strip}
      end
    end.as_java
  end
end

def roll_values txt, dat, &blk
  dat.inject(txt) do |p, n|
    fst, lst, prep, val = n
    lft, rgt = p.split(fst, 2)
    lft +
    if rgt.nil? then
      ''
    else
      cd, rmd   = rgt.split(lst, 2)
      ans       = blk.call cd
      pee       = cd.reverse.split("\n", 2).first.reverse
      (prep.is_a?(String) ? prep : prep.call(cd, pee)) + ans + (val.is_a?(String) ? val : val.call(cd, pee)) + roll_values(rmd, dat, &blk)
    end
  end
end

class Productions
  def initialize
    @zef  = {}
  end

  def []= x, y
    @zef[x] = y
  end

  def [] x
    @zef[x]
  end

  def method_missing meth, *etc
    @zef.method(meth).call *etc
  end

  def one
    @zef[@zef.keys.first]
  end
end

def fmain args
  if args.length < 1 then
    $stderr.puts %[#{$0} production [futamura.xml]]
    return 1
  end
  arg = nil
  prods = ((args[1 .. -1] + ['futamura.xml'])[0 ... 1]).inject(Productions.new) do |p, n|
    File.open n do |fch|
      fut = Hpricot::XML(fch.read)
      (fut / 'production').each do |prd|
        (prd / 'zefania').each do |zef|
          p[prd['name']]  = {zefania: zef['href'], translation:{book: zef['book'], chapter: zef['chapter'], fetch: zef['load']}, work: (prd / 'clay').map do |clay|
            {orig: clay['href'], dest: clay['jar']}
          end}
          if prd['name'] == args.first then
            arg = p[prd['name']]
          end
        end
      end
    end
    p
  end
  if arg.nil? then
    $stderr.puts(%[Known productions: ])
    prods.keys.sort.each do |prd|
      $stderr.puts("%s:\n%s" % [prd, '=' * (prd.length + 1)])
      prods[prd].keys.sort.each do |kys|
        $stderr.puts('%s: %s' % [kys, prods[prd][kys]])
      end
    end
    return 2
  end
  File.open arg[:zefania] do |xfl|
    doc   = Hpricot::XML(xfl.read)
    arg[:work].each do |work|
      File.open work[:orig] do |fch|
        bible = Bible.new((doc / 'XMLBIBLE')[0]['biblename']) do
          (doc / 'BIBLEBOOK').map do |book|
            Book.new book['bname'] do
              (book / 'CHAPTER').map do |chp|
                Chapter.new do
                  (chp / 'VERS').map do |ver|
                    ver.inner_html
                  end
                end
              end
            end
          end
        end
        File.open work[:dest], 'w:UTF-8' do |jar|
          pts = [
            ['null/*',    '*/',   '',     proc { |cd, prep| (prep + "//\n") * (cd.split("\n").length - 1) }],
            ['0/*',       '*/',   '',     proc { |cd, prep| (prep + "//\n") * (cd.split("\n").length - 1) }],
            ['null//',    "\n",   "\n",   ''],
            ['0//',       "\n",   "\n",   ''],
            ['/*//',      '*///', proc { |cd, prep| ((prep + "//\n") * (cd.split("\n").length - 1)) + prep }, '']
          ]
          ans = roll_values(fch.read, pts) do |code|
            $lines  = []
            ans = begin
                    eval code
                  rescue Exception => e
                    $stderr.puts code
                    raise e
                  end
            if $lines.empty? then
              ans
            else
              ($lines + ['']).join(ENV['FUTA_NEW_LINE'] ? "\n" : '; ')
            end
          end
          jar.write ans
        end
      end
    end
  end
  0
end

exit(fmain(ARGV))
