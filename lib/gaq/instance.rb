module Gaq
  class Instance
    extend ActionView::Helpers::JavaScriptHelper

    FLASH_KEY = :analytics_instructions

    def self.finalize
      DSL.finalize
    end

    class InstructionStack
      def self.both_from_flash(flash)
        early, normal = flash[FLASH_KEY] || [[], []]
        [new(early), new(normal)]
      end

      def self.both_into_flash(flash)
        early, normal = flash[FLASH_KEY] = [[], []]
        [new(early), new(normal)]
      end

      def initialize(stack)
        @stack = stack
      end

      def push_with_args(args)
        @stack << Instance.quoted_gaq_item(*args)
      end

      def quoted_gaq_items
        @stack
      end
    end

    module DSL
      # expects InnerDSL to be present

      def push_track_event(category, action, label = nil, value = nil, noninteraction = nil)
        event = [category, action, label, value, noninteraction].compact
        instruction '_trackEvent', *event
      end

      def self.finalize
        Variables.cleaned_up.each do |v|
          define_method "#{v[:name]}=" do |value|
            early_instruction '_setCustomVar', v[:slot], v[:name], value, v[:scope]
          end
        end
      end
    end

    module InnerDSL
      private

      def early_instruction(*args)
        @early_instructions.push_with_args args
      end

      def instruction(*args)
        @instructions.push_with_args args
      end
    end

    class NextRequestProxy
      include DSL
      include InnerDSL

      def initialize
        @early_instructions, @instructions = yield
      end
    end

    include DSL
    include InnerDSL

    def initialize(controller)
      @controller = controller

      @early_instructions, @instructions = InstructionStack.both_from_flash controller.flash
    end

    def next_request
      @next_request ||= NextRequestProxy.new do
        InstructionStack.both_into_flash @controller.flash
      end
    end

    private

    def self.quoted_gaq_item(*args)
      arguments = args.map { |arg| "'#{j arg.to_s}'" }.join ', '
      return "[#{arguments}]"
    end

    def gaq_instructions
      [*static_quoted_gaq_items, *@early_instructions.quoted_gaq_items, *@instructions.quoted_gaq_items]
    end

    def static_quoted_gaq_items
      cls = self.class
      [
        cls.quoted_gaq_item('_setAccount', Gaq.config.web_property_id),
        cls.quoted_gaq_item('_gat._anonymizeIp'),
        cls.quoted_gaq_item('_trackPageview')
      ]
    end

    def js_finalizer
      return '' unless Rails.env.production?
      return <<EOJ
  (function() {
    var ga = document.createElement('script'); ga.type = 'text/javascript'; ga.async = true;
    ga.src = ('https:' == document.location.protocol ? 'https://ssl' : 'http://www') + '.google-analytics.com/ga.js';
    (document.getElementsByTagName('head')[0] || document.getElementsByTagName('body')[0]).appendChild(ga);
  })();
EOJ
    end

    public

    def render(context)
      js_content_lines = [
        'var _gaq = _gaq || [];',
        "_gaq.push(#{gaq_instructions.join(",\n  ")});"
      ]

      js_content = js_content_lines.join("\n") + "\n" + js_finalizer
      context.javascript_tag js_content
    end
  end
end