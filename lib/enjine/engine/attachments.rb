# frozen_string_literal: true

module Enjine
  class Engine
    # Auras and Equipment on the battlefield (CR 301.5, 303.4, 701.3): attaching, and the
    # state-based actions that clean up illegal attachments (CR 704.5m, 704.5n, 704.5p).
    # An attachment remembers the id it is attached to; when that object leaves the
    # battlefield it becomes a new object (CR 400.7), so the stale id is cleaned up here.
    module Attachments
      def aura?(obj) = chars(obj).subtypes.include?(:aura)
      def equipment?(obj) = chars(obj).subtypes.include?(:equipment)

      # The objects attached to `id`, in battlefield order.
      def attachments_of(id) = state.battlefield.select { object(it).attached_to == id }

      # Whether `attachment` could legally be attached to the permanent `target_id` (CR 701.3a).
      def can_attach?(attachment, target_id)
        return false if target_id == attachment.id || !state.battlefield.include?(target_id) # CR 301.5c, 303.4d

        if aura?(attachment)
          enchantable?(attachment, target_id)
        elsif equipment?(attachment)
          !chars(attachment).creature? && chars(target_id).creature? # CR 301.5, 301.5c
        else
          false
        end
      end

      # CR 702.5a, 702.5c, 303.4d: what the Aura's enchant abilities allow (an Aura creature can't enchant).
      def enchantable?(aura, target_id)
        return false if chars(aura).creature?

        enchants = chars(aura).abilities.map(&:ability).select { it.kind == :enchant }
        !enchants.empty? && enchants.all? { it.filter.match_for?(self, target_id, aura.controller, aura.id) }
      end

      # CR 701.3b-c: an illegal attachment doesn't move; reattaching to the same object does nothing.
      def attach!(attachment, target_id)
        return false if attachment.attached_to == target_id || !can_attach?(attachment, target_id)

        attachment.attached_to = target_id
        emit Events::Attached.new(object: attachment.id, to: target_id)
        true
      end

      # CR 701.3d: unattach (the permanent stays on the battlefield).
      def unattach!(attachment)
        from = attachment.attached_to or return
        attachment.attached_to = nil
        emit Events::Unattached.new(object: attachment.id, from: from)
      end

      # CR 704.5m: an Aura attached to an illegal object, or to nothing, goes to the graveyard.
      def illegal_aura?(obj)
        return false unless aura?(obj)

        to = obj.attached_to
        to.nil? || !can_attach?(obj, to)
      end

      # CR 704.5n (Equipment attached to an illegal permanent) and 704.5p (anything that's neither
      # an Aura nor an Equipment, e.g. a permanent that stopped being one): it becomes unattached.
      # Returns true when anything was unattached.
      def unattach_illegal_attachments!
        loose = state.battlefield.select do |id|
          obj = object(id)
          obj.attached_to && !aura?(obj) && !can_attach?(obj, obj.attached_to)
        end
        loose.each { unattach!(object(it)) }
        !loose.empty?
      end
    end
    include Attachments
  end
end
