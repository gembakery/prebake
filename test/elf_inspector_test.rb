# frozen_string_literal: true

require "test_helper"
require "prebake/elf_inspector"

class ElfInspectorTest < Minitest::Test
  def test_parse_glibc_version_picks_highest
    output = <<~OBJDUMP
      0000000000000000      DF *UND*	0000000000000000 (GLIBC_2.2.5) __libc_start_main
      0000000000000000      DF *UND*	0000000000000000 (GLIBC_2.14) memcpy
      0000000000000000      DF *UND*	0000000000000000 (GLIBC_2.34) __stack_chk_fail
    OBJDUMP

    assert_equal "2.34", Prebake::ElfInspector.parse_glibc_version(output)
  end

  def test_parse_glibc_version_handles_three_part_version
    output = "0000000 DF *UND* (GLIBC_2.2.5) foo"

    assert_equal "2.2.5", Prebake::ElfInspector.parse_glibc_version(output)
  end

  def test_parse_glibc_version_returns_nil_without_glibc_references
    output = "0000000 DF *UND* some_symbol"

    assert_nil Prebake::ElfInspector.parse_glibc_version(output)
  end

  def test_parse_glibc_version_returns_nil_for_empty_string
    assert_nil Prebake::ElfInspector.parse_glibc_version("")
  end

  def test_required_glibc_returns_nil_when_file_missing
    assert_nil Prebake::ElfInspector.required_glibc("/nonexistent/path.so")
  end

  def test_required_glibc_returns_nil_when_objdump_unavailable
    Prebake::ElfInspector.stubs(:run_objdump).returns(nil)

    Tempfile.create(["fake", ".so"]) do |f|
      assert_nil Prebake::ElfInspector.required_glibc(f.path)
    end
  end

  def test_required_glibc_returns_parsed_version_from_objdump_output
    Prebake::ElfInspector.stubs(:run_objdump).returns(
      "0000000 DF *UND* (GLIBC_2.28) foo\n0000000 DF *UND* (GLIBC_2.17) bar"
    )

    Tempfile.create(["fake", ".so"]) do |f|
      assert_equal "2.28", Prebake::ElfInspector.required_glibc(f.path)
    end
  end

  def test_required_glibc_for_gem_returns_highest_across_binaries
    gem_path = build_test_gem(files: { "foo.so" => "x", "bar.so" => "y" })

    Prebake::ElfInspector.stubs(:required_glibc).with(regexp_matches(/foo\.so\z/)).returns("2.28")
    Prebake::ElfInspector.stubs(:required_glibc).with(regexp_matches(/bar\.so\z/)).returns("2.35")

    assert_equal "2.35", Prebake::ElfInspector.required_glibc_for_gem(gem_path)
  end

  def test_required_glibc_for_gem_returns_nil_when_no_binaries
    gem_path = build_test_gem(files: { "lib/foo.rb" => "# ruby only" })

    assert_nil Prebake::ElfInspector.required_glibc_for_gem(gem_path)
  end

  def test_required_glibc_for_gem_returns_nil_when_no_binary_reports_version
    gem_path = build_test_gem(files: { "foo.so" => "x" })
    Prebake::ElfInspector.stubs(:required_glibc).returns(nil)

    assert_nil Prebake::ElfInspector.required_glibc_for_gem(gem_path)
  end

  def test_required_glibc_for_gem_returns_nil_for_malformed_gem
    tmpdir = Dir.mktmpdir
    bad = File.join(tmpdir, "not-a.gem")
    File.write(bad, "garbage")

    assert_nil Prebake::ElfInspector.required_glibc_for_gem(bad)
  ensure
    FileUtils.rm_rf(tmpdir) if tmpdir
  end

  def test_needed_libraries_returns_empty_for_missing_file
    assert_equal [], Prebake::ElfInspector.needed_libraries("/nonexistent/path.so")
  end

  def test_needed_libraries_returns_empty_when_objdump_unavailable
    Prebake::ElfInspector.stubs(:run_objdump_p).returns(nil)

    Tempfile.create(["fake", ".so"]) do |f|
      Prebake::ElfInspector.stubs(:needed_libraries).with(f.path).returns([])
      assert_equal [], Prebake::ElfInspector.needed_libraries(f.path)
    end
  end

  def test_needed_libraries_parses_needed_entries_from_objdump
    Tempfile.create(["fake", ".so"]) do |f|
      out = <<~OBJDUMP
        Dynamic Section:
          NEEDED               libpthread.so.0
          NEEDED               libruby.so.4.0
          NEEDED               libc.so.6
      OBJDUMP
      Open3.stubs(:capture2e).with("objdump", "-p", f.path).returns([out, stub(success?: true)])

      assert_equal %w[libpthread.so.0 libruby.so.4.0 libc.so.6],
                   Prebake::ElfInspector.needed_libraries(f.path)
    end
  end

  def test_libruby_needed_returns_true_when_libruby_in_needed
    Prebake::ElfInspector.stubs(:needed_libraries).returns(["libpthread.so.0", "libruby.so.4.0"])
    assert Prebake::ElfInspector.libruby_needed?("/fake.so")
  end

  def test_libruby_needed_returns_false_when_libruby_absent
    Prebake::ElfInspector.stubs(:needed_libraries).returns(["libpthread.so.0", "libc.so.6"])
    refute Prebake::ElfInspector.libruby_needed?("/fake.so")
  end

  def test_libruby_needed_for_gem_returns_true_when_binary_needs_libruby
    gem_path = build_test_gem(files: { "ext.so" => "x" })
    Prebake::ElfInspector.stubs(:libruby_needed?).with(regexp_matches(/ext\.so\z/)).returns(true)

    assert Prebake::ElfInspector.libruby_needed_for_gem?(gem_path)
  end

  def test_libruby_needed_for_gem_returns_false_when_no_binary_needs_libruby
    gem_path = build_test_gem(files: { "ext.so" => "x" })
    Prebake::ElfInspector.stubs(:libruby_needed?).returns(false)

    refute Prebake::ElfInspector.libruby_needed_for_gem?(gem_path)
  end

  def test_libruby_needed_for_gem_returns_false_when_no_binaries
    gem_path = build_test_gem(files: { "lib/foo.rb" => "# ruby" })

    refute Prebake::ElfInspector.libruby_needed_for_gem?(gem_path)
  end

  def test_libruby_needed_for_gem_returns_false_for_malformed_gem
    tmpdir = Dir.mktmpdir
    bad = File.join(tmpdir, "not-a.gem")
    File.write(bad, "garbage")

    refute Prebake::ElfInspector.libruby_needed_for_gem?(bad)
  ensure
    FileUtils.rm_rf(tmpdir) if tmpdir
  end
end
