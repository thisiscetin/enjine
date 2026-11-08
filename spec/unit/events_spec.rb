# frozen_string_literal: true

RSpec.describe Enjine::Events do
  let(:draw) do
    Enjine::Events::ZoneChanged.new(card: "forest", old_id: "forest#1", new_id: "forest#2", owner: "alice",
                                    from: "library", to: "hand", reason: "draw")
  end

  it "serializes with a type" do
    expect(draw.to_h).to include("type" => "zone_changed", "card" => "forest")
  end

  it "redacts hidden-to-hidden moves for other players" do
    expect(draw.for_viewer("alice")).to eq(draw.to_h)
    expect(draw.for_viewer(:observer)).to eq(draw.to_h)
    expect(draw.for_viewer("bob")).to eq("type" => "zone_changed", "owner" => "alice", "from" => "library",
                                         "to" => "hand", "reason" => "draw")
  end

  it "shows moves into public zones to everyone" do
    play = draw.with(from: "hand", to: "battlefield", reason: "play_land")
    expect(play.for_viewer("bob")).to eq(play.to_h)
  end

  it "rebuilds events from their hash form" do
    expect(described_class.from_h(draw.to_h)).to eq(draw)
    expect { described_class.from_h("type" => "nope") }.to raise_error(ArgumentError)
  end
end
