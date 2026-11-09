# frozen_string_literal: true

module Enjine
  class Engine
    # The rest of a replacement or prevention effect, done right after the event it modified (CR 615.5,
    # 614.1a): "... and put that many +1/+1 counters on him", "... and you gain 2 life", "When you do, ..."
    # (Mechanics::FollowUp). A replacement adds an entry to the event's data["follow_ups"].
    module FollowUps
      # `facts` overrides the entries' facts (the card exiled instead, known once the move is done). An entry
      # with "link" links that card to its source ("exiled with [it]", CR 607.2a).
      def run_follow_ups!(data, facts = {})
        Array(data.delete("follow_ups")).each do |entry|
          seen = entry["facts"].merge(facts).compact
          link_exiled!(entry["source"], seen["object"]) if entry["link"] && seen["object"]
          next unless entry["ref"]

          effects = catalog.fetch(entry["card"]).ability(entry["ref"]).effects
          memory = { "triggering" => seen, "source_card" => entry["card"] }
          ctx = Mechanics::EffectContext.new(entry["controller"], entry["source"], entry["source"], [], [], [], memory)
          effects.each { it.run(self, ctx, {}) } # effects that need no choice (CR 615.5)
        end
      end
    end

    include FollowUps
  end
end
