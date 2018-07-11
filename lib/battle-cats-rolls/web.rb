# frozen_string_literal: true

require_relative 'crystal_ball'
require_relative 'gacha'
require_relative 'exclusive_cat'

require 'jellyfish'

require 'cgi'
require 'erb'
require 'date'
require 'forwardable'

module BattleCatsRolls
  class Web
    Max = 999

    def self.ball
      @ball ||= CrystalBall.load('build/7.1.0')
    end

    class View < Struct.new(:controller, :arg)
      extend Forwardable

      def_delegators :controller,
        *%w[request gacha upcoming_events past_events]

      def render name
        erb(:layout){ erb(name) }
      end

      def each_ab_cat
        arg[:cats].each.inject(nil) do |prev_b, ab|
          next_a = arg.dig(:cats, ab.dig(0, :sequence), 0)

          yield(prev_b, ab, next_a)

          ab.last
        end
      end

      def guaranteed_cat cat, offset
        if guaranteed = cat.guaranteed
          next_sequence = cat.sequence + arg[:guaranteed_rolls] + offset
          next_cat = arg.dig(:cats, next_sequence - 1, offset)
                               # Back to count from 0, ^ Swap track!
          link = link_to_roll(guaranteed, next_cat)

          if offset < 0
            "#{link}<br>-&gt; #{next_sequence}"
          else
            "#{link}<br>&lt;- #{next_sequence}"
          end
        end
      end

      def link_to_roll cat, next_cat=nil
        if next_cat
          %Q{<a href="#{h uri_to_roll(next_cat)}">#{h cat.name}</a>}
        else
          h cat.name
        end + %Q{<a href="#{h uri_to_cat_db(cat)}">&#128062;</a>}
      end

      def selected_current_event event_name
        'selected="selected"' if controller.event == event_name
      end

      def checked_show_seeds
        'checked="checked"' if show_seeds
      end

      def show_event info
        h "#{info['start_on']} ~ #{info['end_on']}: #{info['name']}"
      end

      def h str
        CGI.escape_html(str)
      end

      def u str
        CGI.escape(str)
      end

      private

      def seed_column
        yield if show_seeds
      end

      def show_seeds
        return @show_seeds if instance_variable_defined?(:@show_seeds)

        @show_seeds = !request.GET['show_seeds'].to_s.strip.empty? || nil
      end

      def uri_to_roll cat
        uri(seed: cat.rarity_seed,
            event: controller.event,
            count: controller.count,
            show_seeds: show_seeds)
      end

      def uri_to_cat_db cat
        "https://battlecats-db.com/unit/#{'%03d' % cat.id}.html"
      end

      def uri query={}
        query_string = query.map do |key, value|
          "#{u key.to_s}=#{u value.to_s}"
        end.join('&')

        path = "#{request.base_url}#{request.path}"

        if query.empty?
          path
        else
          "#{path}?#{query_string}"
        end
      end

      def erb name, &block
        ERB.new(views(name)).result(binding, &block)
      end

      def views name
        File.read("#{__dir__}/view/#{name}.erb")
      end
    end

    module Imp
      def gacha
        @gacha ||= Gacha.new(Web.ball, event, seed)
      end

      def seed
        @seed ||= request.GET['seed'].to_i
      end

      def event
        @event ||= request.GET['event'] || current_event
      end

      def count
        @count ||= [1, [(request.GET['count'] || 100).to_i, Max].min].max
      end

      def current_event
        @current_event ||=
          upcoming_events.find{ |_, info| info['platinum'].nil? }&.first
      end

      def upcoming_events
        @upcoming_events ||= all_events[true]
      end

      def past_events
        @past_events ||= all_events[false]
      end

      def all_events
        @all_events ||= begin
          today = Date.today

          Web.ball.dig('events').group_by do |key, value|
            today <= value['end_on']
          end
        end
      end

      def render name, arg=nil
        View.new(self, arg).render(name)
      end
    end

    include Jellyfish
    controller_include NormalizedPath, Imp

    get '/' do
      if event && seed != 0
        # Human counts from 1
        cats = 1.upto(count).map do |sequence|
          gacha.roll_both_with_sequence!(sequence)
        end

        guaranteed_rolls = gacha.fill_guaranteed(cats)
        exclusive_cats = ExclusiveCat.search(gacha, cats: cats, max: Max)

        render :index,
          cats: cats,
          guaranteed_rolls: guaranteed_rolls,
          exclusive_cats: exclusive_cats
      else
        render :index
      end
    end
  end
end
