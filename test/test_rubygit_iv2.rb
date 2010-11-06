require File.dirname(__FILE__) + '/helper'
require 'pp'

class TestRubyGitIv2 < Test::Unit::TestCase

  def setup
    @base_repo = create_temp_repo(File.join(File.dirname(__FILE__), *%w[dot_git_iv2]))
    @git = Grit::Repo.new(@base_repo, :is_bare => true)
    @rgit = @git.git.ruby_git
    @commit_sha = 'ca8a30f5a7f0f163bbe3b6f0abf18a6c83b0687a'
    @tree_sha   = 'cd7422af5a2e0fff3e94d6fb1a8fff03b2841881'
    @blob_sha   = '4232d073306f01cf0b895864e5a5cfad7dd76fce'
  end

  def create_temp_repo(clone_path)
    filename = 'git_test' + Time.now.to_i.to_s + rand(300).to_s.rjust(3, '0')
    tmp_path = File.join("/tmp/", filename)
    FileUtils.mkdir_p(tmp_path)
    FileUtils.cp_r(clone_path, tmp_path)
    File.join(tmp_path, 'dot_git_iv2')
  end

  def test_basic
    assert @rgit.object_exists?(@commit_sha)
    assert_equal 10, @git.commits.size
  end

  def test_objects
    commit = @rgit.get_object_by_sha1(@commit_sha)
    assert_equal commit.author.email, 'schacon@gmail.com'
    tree = @rgit.get_object_by_sha1(@tree_sha)
    assert_equal 7, tree.entry.size
    blob = @rgit.get_object_by_sha1(@blob_sha)
    assert_match 'First public release', blob.content
  end

  def test_write_loose_file
    actual_size = File.size(__FILE__)
    content     = File.new(__FILE__, 'r')

    sha = @rgit.put_raw_object(content, 'blob')
    obj = @rgit.get_object_by_sha1(sha)

    assert_equal :blob,             obj.type
    assert_equal IO.read(__FILE__), obj.content
  end
end