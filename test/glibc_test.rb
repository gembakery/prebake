# frozen_string_literal: true

require "test_helper"
require "prebake/glibc"

class GlibcTest < Minitest::Test
  def setup
    Prebake::Glibc.reset!
  end

  def teardown
    Prebake::Glibc.reset!
  end

  def test_parse_version_from_gnu_ldd_output
    output = <<~LDD
      ldd (Ubuntu GLIBC 2.35-0ubuntu3.4) 2.35
      Copyright (C) 2022 Free Software Foundation, Inc.
    LDD

    assert_equal "2.35", Prebake::Glibc.parse_version(output)
  end

  def test_parse_version_handles_debian_style
    output = "ldd (Debian GLIBC 2.36-9+deb12u4) 2.36\n"

    assert_equal "2.36", Prebake::Glibc.parse_version(output)
  end

  def test_parse_version_handles_fedora_rhel_style
    output = "ldd (GNU libc) 2.34\nCopyright (C) 2021 Free Software Foundation, Inc.\n"

    assert_equal "2.34", Prebake::Glibc.parse_version(output)
  end

  def test_parse_version_returns_nil_for_musl_output
    output = "musl libc (x86_64)\nVersion 1.2.3\n"

    assert_nil Prebake::Glibc.parse_version(output)
  end

  def test_parse_version_returns_nil_for_empty_output
    assert_nil Prebake::Glibc.parse_version("")
  end

  def test_compatible_true_when_required_is_nil
    Prebake::Glibc.stubs(:linux?).returns(true)
    Prebake::Glibc.stubs(:detected_version).returns("2.28")

    assert Prebake::Glibc.compatible?(nil)
  end

  def test_compatible_true_on_non_linux_regardless
    Prebake::Glibc.stubs(:linux?).returns(false)

    assert Prebake::Glibc.compatible?("2.99")
  end

  def test_compatible_true_when_detected_matches_required
    Prebake::Glibc.stubs(:linux?).returns(true)
    Prebake::Glibc.stubs(:detected_version).returns("2.35")

    assert Prebake::Glibc.compatible?("2.35")
  end

  def test_compatible_true_when_detected_exceeds_required
    Prebake::Glibc.stubs(:linux?).returns(true)
    Prebake::Glibc.stubs(:detected_version).returns("2.39")

    assert Prebake::Glibc.compatible?("2.28")
  end

  def test_compatible_false_when_detected_below_required
    Prebake::Glibc.stubs(:linux?).returns(true)
    Prebake::Glibc.stubs(:detected_version).returns("2.28")

    refute Prebake::Glibc.compatible?("2.35")
  end

  def test_compatible_false_on_linux_when_detection_fails
    Prebake::Glibc.stubs(:linux?).returns(true)
    Prebake::Glibc.stubs(:detected_version).returns(nil)

    refute Prebake::Glibc.compatible?("2.35")
  end

  def test_detected_version_is_cached
    Prebake::Glibc.expects(:run_ldd).returns("ldd (GNU libc) 2.35\n").once

    Prebake::Glibc.detected_version
    Prebake::Glibc.detected_version
  end
end
