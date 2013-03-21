require 'gaq/instruction/base'

module Gaq
  module Instruction
    class TrackPageview < Base
      stack_position :setup

      tracker_method '_trackPageview'

      signature String
    end
  end
end
