#
# converted from the gitrb project
#
# authors:
#    Matthias Lederhofer <matled@gmx.net>
#    Simon 'corecode' Schubert <corecode@fs.ei.tum.de>
#    Scott Chacon <schacon@gmail.com>
#
# provides native ruby access to git objects and pack files
#

require 'zlib'
require 'digest/sha1'
require 'grit/git-ruby/internal/raw_object'

module Grit
  module GitRuby
    module Internal
      class LooseObjectError < StandardError
      end

      class LooseStorage
        def initialize(directory)
          @directory = directory
        end

        def [](sha1)
          sha1 = sha1.unpack("H*")[0]
          begin
            return nil unless sha1[0...2] && sha1[2..39]
            path = @directory + '/' + sha1[0...2] + '/' + sha1[2..39]
            get_raw_object(open(path, 'rb') { |f| f.read })
          rescue Errno::ENOENT
            nil
          end
        end

        def get_raw_object(buf)
          if buf.length < 2
            raise LooseObjectError, "object file too small"
          end

          if legacy_loose_object?(buf)
            content = Zlib::Inflate.inflate(buf)
            header, content = content.split(/\0/, 2)
            if !header || !content
              raise LooseObjectError, "invalid object header"
            end
            type, size = header.split(/ /, 2)
            if !%w(blob tree commit tag).include?(type) || size !~ /^\d+$/
              raise LooseObjectError, "invalid object header"
            end
            type = type.to_sym
            size = size.to_i
          else
            type, size, used = unpack_object_header_gently(buf)
            content = Zlib::Inflate.inflate(buf[used..-1])
          end
          raise LooseObjectError, "size mismatch" if content.length != size
          return RawObject.new(type, content)
        end

        # Public: Writes a Git object to disk, using the SHA1 of the content 
        # as the filename.  This uses the legacy format for Git objects.
        #
        # content - The object's content as a String or IO object.
        # type    - A String specifying the object's type: 
        #           "blob", "tree", "commit", or "tag"
        # size    - Optional Fixnum size of the content.  If not given, read
        #           the content to get the size.
        #
        # Returns a String SHA1 of the Git object, which is also the filename.
        def put_raw_object(content, type, size = nil)
          self.class.calculate_header(content, type, size) do |sha, size, io, header|
            prefix = sha[0...2]
            suffix = sha[2..40]
            path   = "#{@directory}/#{prefix}"
            full   = "#{path}/#{suffix}"

            return sha if File.exists?(full)
            FileUtils.mkdir_p(path)
            File.open(full, 'wb') do |f| 
              zip = Zlib::Deflate.new
              f << zip.deflate(header)
              while data = io.read(4096)
                f << zip.deflate(data)
              end
              f << zip.finish
              zip.close
            end

            sha
          end
        end

        # Generates the Git object's header for the loose format, as well
        # as the SHA of the loose object.
        #
        # content - The object's content as an IO object.
        # type    - A String specifying the object's type: 
        #           "blob", "tree", "commit", or "tag"
        # size    - Fixnum size of the content.
        #
        # Yields the String SHA, the content size, the content IO instance,
        # and the String header if a block is given.
        # Returns the block's output if a block is given, or a Hash of the 
        # block's contents.
        def self.calculate_header(content, type, size = nil)
          if !content.respond_to?(:read)
            content = StringIO.new(content.to_s)
          end

          size ||= get_content_size(content)
          head   = verify_header(type, size.to_s)

          sha = Digest::SHA1.new
          sha << head
          while data = content.read(4096)
            sha << data
          end
          content.rewind

          if block_given?
            yield sha.hexdigest, size, content, head
          else
            {:size => size, :sha => sha.hexdigest, :header => head, 
              :content => content}
          end
        end

        # Calculates the Git object's header and returns the sha.
        #
        # content - The object's content as an IO object.
        # type    - A String specifying the object's type: 
        #           "blob", "tree", "commit", or "tag"
        # size    - Fixnum size of the content.
        #
        # Returns the String SHA of the Git loose object.
        def self.calculate_sha(content, type, size = nil)
          calculate_header { |_, sha| sha }
        end

        # Gets the size of the given content by counting the bytes.
        #
        # content - The object's content as an IO object.
        #
        # Returns the Fixnum size of the content.
        def self.get_content_size(content)
          if content.respond_to?(:size)
            content.size
          else
            size = 0
            while data = content.read(4096)
              size += data.size
            end
            content.rewind
            size
          end
        end

        VALID_OBJECTS = %w(blob tree commit tag)

        # Creates a valid header for Git loose objects.
        #
        # type    - A String specifying the object's type: 
        #           "blob", "tree", "commit", or "tag"
        # size    - Fixnum size of the content.
        #
        # Raises LooseObjectError if the header is invalid.
        # Returns a String if the header data is valid.
        def self.verify_header(type, size)
          header = "#{type} #{size}\0"
          if VALID_OBJECTS.include?(type) && size =~ /^\d+$/
            header
          else
            raise LooseObjectError, "invalid object header: #{header.inspect}"
          end
        end

        # private
        def unpack_object_header_gently(buf)
          used = 0
          c = buf.getord(used)
          used += 1

          type = (c >> 4) & 7;
          size = c & 15;
          shift = 4;
          while c & 0x80 != 0
            if buf.length <= used
              raise LooseObjectError, "object file too short"
            end
            c = buf.getord(used)
            used += 1

            size += (c & 0x7f) << shift
            shift += 7
          end
          type = OBJ_TYPES[type]
          if ![:blob, :tree, :commit, :tag].include?(type)
            raise LooseObjectError, "invalid loose object type"
          end
          return [type, size, used]
        end
        private :unpack_object_header_gently

        def legacy_loose_object?(buf)
          word = (buf.getord(0) << 8) + buf.getord(1)
          buf.getord(0) == 0x78 && word % 31 == 0
        end
        private :legacy_loose_object?
      end
    end
  end
end
