# Copyright (c) 2006 Nathan Wilson
# Licensed under the MIT License: http://www.opensource.org/licenses/mit-license.php

# These are used to create temporary storage that acts like a normal
# database column.  They're used (implicity no doubt) inside the
# create/construc/edit/update_observation/naming views/forms.
# [I've removed them, since I think I've obviated their need. -JPH 20071124]
#   what=(string)
#   what
#
# Name formating:
#   text_name               Plain text.  (uses name.search_name)
#   format_name             Textilized.  (uses name.observation_name)
#   unique_text_name        Same as above, with id added to make unique.
#   unique_format_name
#   [What and base_name were confusing and inconsistent. -JPH 20071123]
#
# Voting and preferences:
#   vote_sum                Straight sum of votes for this naming.
#   vote_percent            Convert cached vote score to a percentage.
#   user_voted?(user)       Has a given user voted on this naming?
#   users_vote(user)        Get a given user's vote on this naming.
#   calc_vote_table         Used by show_votes.rhtml
#   change_vote(user, val)  Change a user's vote for this naming.
#   is_owners_favorite?     Is this (one of) the owner's favorite(s)?
#   is_users_favorite?(user) Is this (one of) the user's favorite(s)?
#   is_consensus?           Is this the community consensus?
#   editable?               Has anyone voted (positively) on this naming?
#   deletable?              Has anyone made this naming their favorite?
#   N.refresh_vote_cache    Monster sql query to refresh all vote_caches.

class Naming < ActiveRecord::Base
  belongs_to :observation
  belongs_to :name
  belongs_to :user
  has_many   :naming_reasons,    :dependent => :destroy
  has_many   :votes,             :dependent => :destroy

  # Various name formats.
  def text_name
    self.name.search_name
  end
  
  def unique_text_name
    str = self.name.search_name
    "%s (%s)" % [str, self.id]
  end
  
  def format_name
    self.name.observation_name
  end

  def unique_format_name
    str = self.name.observation_name
    "%s (%s)" % [str, self.id]
  end

  # Just used by functional tests right now.
  def vote_sum
    sum = 0
    for v in self.votes
      sum += v.value
    end
    return sum
  end

  # Just convert vote_cache to a percentage.
  def vote_percent
    v = self.vote_cache
    return 0.0 if v.nil? || v == ""
    return v * 100 / 3
  end

  # Has a given user voted for this naming?
  def user_voted?(user)
    return false if !user || !user.verified
    vote = self.votes.find(:first,
      :conditions => ['user_id = ?', user.id])
    return vote ? true : false
  end

  # Retrieve a given user's vote for this naming.
  def users_vote(user)
    return false if !user || !user.verified
    self.votes.find(:first,
      :conditions => ['user_id = ?', user.id])
  end

  # Create the structure used by show_votes view:
  # Just a table of number of users who cast each level of vote.
  def calc_vote_table
    table = Hash.new
    for str, val in Vote.agreement_menu
      table[str] = {
        :num   => 0,
        :wgt   => 0,
        :value => val,
        :users => [],
      }
    end
    tot_sum = 0
    tot_wgt = 0
    for v in self.votes
      str = v.agreement
      wgt = v.user_weight
      table[str][:wgt] += wgt
      table[str][:num] += 1
      tot_sum += v.value * wgt
      tot_wgt += wgt
    end
    val = tot_sum.to_f / (tot_wgt + 1.0)
    if self.vote_cache != val
      self.vote_cache = val
      self.save
    end
    return table
  end

  # Change user's vote for this naming.  Automatically recalculates the
  # consensus for the observation in question if anything is changed.
  # Returns: true if something was changed.
  def change_vote(user, value)
    vdel = Vote.delete_vote
    v100 = Vote.maximum_vote
    v80  = Vote.next_best_vote
    vote = self.votes.find(:first,
      :conditions => ['user_id = ?', user.id])
    # Negative value means destroy vote.
    if value == vdel
      return false if !vote
      vote.destroy
    # Otherwise create new vote or modify existing vote.
    else
      return false if vote && vote.value == value
      now = Time.now
      # First downgrade any existing 100% votes (if casting a 100% vote).
      if value == v100
        for n in self.observation.namings
          v = n.users_vote(user)
          if v && v.value == v100
            v.modified = now
            v.value    = v80
            v.save
          end  
        end
      end
      # Now create/change vote.
      if !vote
        vote = Vote.new
        vote.created     = now
        vote.user        = user
        vote.naming      = self
        vote.observation = self.observation
      end
      vote.modified = now
      vote.value    = value
      vote.save
    end
    # Update cached score.
    sum = 0
    wgt = 0
    for v in self.votes
      w = v.user_weight
      sum += v.value * w
      wgt += w
    end
    sum /= wgt + 1.0
    if self.vote_cache != sum
      self.vote_cache = sum
      self.save
    end
    # Update consensus.
    self.observation.calc_consensus
    return true
  end

  # Has anyone voted (positively) on this?  We don't want people changing
  # the name for namings that the community has voted on.
  # Returns true if no one has.
  def editable?
    for v in self.votes
      return false if v.user_id != self.user_id and v.value > 0
    end
    return true
  end

  # Has anyone given this their strongest (positive) vote?  We don't want people
  # destroying namings that someone else likes best.
  # Returns true if no one has.
  def deletable?
    for v in self.votes
      if v.user_id != self.user_id and v.value > 0
        return false if self.is_users_favorite?(v.user)
      end
    end
    return true
  end

  # Returns true if this naming has received the highest positive vote
  # from the owner of the corresponding observation.  Note, multiple namings
  # can return true for a given observation.
  def is_owners_favorite?
    self.is_users_favorite?(self.observation.user)
  end

  # Returns true if this naming has received the highest positive vote
  # from the given user (among namings for the corresponding observation).
  # Note, multiple namings can return true for a given user and observation.
  def is_users_favorite?(user)
    obs = self.observation
    if obs
      # was
      # votes = user.votes.select {|v| v.naming.observation == obs}
      votes = Vote.find_all_by_observation_id_and_user_id(obs.id, user.id)
      max = 0
      for vote in votes
        max = vote.value if vote.value > 0 && vote.value > max
      end
      if max > 0
        for vote in votes
          return true if vote.naming == self && vote.value == max
        end
      end
    end
    return false
  end

  # If the community consensus clearly derives from a single naming, then this will
  # return true for that naming.  Otherwise it returns false for everything else.
  def is_consensus?
    self.observation.name == self.name
  end

  # Refresh the vote_cache column across all namings.  Used my db:migrate and
  # admin tool.
  def self.refresh_vote_cache
    self.connection.update %(
      UPDATE namings
      SET vote_cache=(
        SELECT sum(votes.value)/(count(votes.value)+1)
        FROM votes
        WHERE namings.id = votes.naming_id
      )
    )
  end

  validates_presence_of :name, :observation, :user
end