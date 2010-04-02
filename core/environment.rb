# -*- coding: utf-8 -*-
#
# Envirionment
#

# 変更不能な設定たち
# コアで変更されるもの

miquire :core, 'config'

module Environment
  # このアプリケーションの名前。
  NAME = Config::NAME

  # 名前の略称
  ACRO = Config::ACRO

  # pidファイル
  PIDFILE = Config::PIDFILE

  # コンフィグファイルのディレクトリ
  CONFROOT = Config::CONFROOT

  # 一時ディレクトリ
  TMPDIR = Config::TMPDIR

  # ログディレクトリ
  LOGDIR = Config::LOGDIR

  # AutoTag有効？
  AutoTag = Config::AutoTag

  # 再起動後に、前回取得したポストを取得しない
  NeverRetrieveOverlappedMumble = Config::NeverRetrieveOverlappedMumble

  class Version
    include Comparable

    attr_reader :mejor, :minor, :debug, :devel

    def initialize(mejor, minor=1.0/0, debug=1.0/0, devel=1.0/0)
      @mejor = mejor
      @minor = minor
      @debug = debug
      @devel = devel
    end

    def to_a
      [@mejor, @minor, @debug, @devel]
    end

    def to_s
      self.to_a.join('.')
    end

    def to_i
      @mejor
    end

    def to_f
      @mejor + @minor/100
    end

    def inspect
      "#{Environment::NAME} ver.#{self.to_s}"
    end

    def size
      4
    end

    def <=>(other)
      if other.size == 4 then
        self.to_a <=> other.to_a
      end
    end

  end

  # このソフトのバージョン。
  VERSION = Version.new(0,0,1,1)

end