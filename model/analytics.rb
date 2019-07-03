class Analytics
  include ActiveModel::Model

  attr_accessor :filter

  def initialize (f = {})
    @filter = f
    setDefault
  end
  # Analytics data
  def getData
    if @filter[:entity] == 'votes'
      Tracking.collection.aggregate([
        { "$match": 
          {
            "action": "vote",
            "asked_to": @filter[:loggedin_user_id],
            "created_at": { "$gte": @filter[:from_date], "$lt": @filter[:to_date] }
          }
        },
        { 
          "$sort": { "created_at": -1 }
        },
        { "$group": 
          { "_id": group_by, 
            "male_votes": {"$sum":{"$cond":[{"$eq":["$actor_gender", "male"]},1,0]} },

            "female_votes": {"$sum":{"$cond":[{"$eq":["$actor_gender", "female"]},1,0]}}, 

            "other_votes": {"$sum":{"$cond":[{"$eq":["$actor_gender", "unknown"]},1,0]}}, 

            "total_votes": {"$sum":1}
          }
        }
      ])
    else
      Question.collection.aggregate([
        { "$match": 
          {
            "asked_to": @filter[:loggedin_user_id],
            "created_at": { "$gte": @filter[:from_date], "$lt": @filter[:to_date] }
          }
        },
        { 
          "$sort": { "created_at": -1 }
        },
        { "$group": 
          { "_id": group_by, 
            "male": {"$sum":{"$cond":[{"$eq":["$asker_gender", "male"]},1,0]} },

            "female": {"$sum":{"$cond":[{"$eq":["$asker_gender", "female"]},1,0]}}, 

            "other": {"$sum":{"$cond":[{"$eq":["$asker_gender", "unknown"]},1,0]}}, 

            "total": {"$sum":1}
          }
        }
      ])
    end
  end

  def getDataCount (data = {})
    questions = Question.where(asked_to: @filter[:loggedin_user_id], created_at: @filter[:from_date]..@filter[:to_date])
    data[:asker_gender] = questions.max(:asker_gender) rescue 0
    data[:questions] = questions.count rescue 0
    data[:questions_region] = questions.max(:state_name) rescue nil
    data[:questions_city] = questions.max(:city) rescue nil
    data[:questions_zipcode] = questions.max(:postal_code) rescue nil
    data[:question_sentiment] = questions.avg(:sentiment) rescue 0

    votes = Tracking.where(action: 'vote',asked_to: @filter[:loggedin_user_id], created_at: @filter[:from_date]..@filter[:to_date])
    data[:votes] = votes.try(:count) rescue 0
    data[:voting_region] = votes.max(:state_name) rescue nil
    data[:voting_city] = votes.max(:city) rescue nil
    data[:voting_zipcode] = votes.max(:postal_code) rescue nil

    data[:answers] = Question.where(answerers: @filter[:loggedin_user_id], created_at: @filter[:from_date]..@filter[:to_date]).count  rescue 0
    data
  end

  # Statistics data
  def getQuestions
    questions = if @filter[:offset] == 'infinite'
        Question.where( asked_to: @filter[:loggedin_user_id] )
      else
        Question.where( asked_to: @filter[:loggedin_user_id], created_at: @filter[:from_date]..@filter[:to_date] )
      end

    questions = case @filter[:answered]
      when 1      
        questions.where( answerers: @filter[:loggedin_user_id] )
      when 0
        questions.where( :answerers.ne => @filter[:loggedin_user_id] )
      else
        questions
      end
    questions = questions.where(asker_gender: @filter[:gender]) if @filter[:gender]
    questions = questions.where( "this.asked_to.length #{asked_to_length}" ) if @filter[:debate]
    questions = questions.where(state_code: @filter[:state]) if @filter[:state].present?
    questions = questions.where(city: Regexp.new( Regexp.escape(@filter[:city]), "i" )) if @filter[:city].present?
    questions = questions.where(sentiment: @filter[:sentiment_from]..@filter[:sentiment_to]) if @filter[:sentiment_from].present?
    questions = questions.where(requestor_count: @filter[:vcount_from]..@filter[:vcount_to]) if @filter[:vcount_from].present?
    questions = questions.order(@filter[:sort_by]) if @filter[:sort_by].present?
    questions.paginate( page: @filter[:page], per_page: APP_CONFIG[:questions_per_page])
  end

  # Question analytics
  def getQuestionData
    match_by = if @filter[:offset]=="infinite"
        {
          "question_id": @filter[:q_id],
          "action": 'vote'
        }
      else
        {
          "question_id": @filter[:q_id],
          "action": 'vote',
          "created_at": { 
            "$gte":  @filter[:from_date],
            "$lte":  @filter[:to_date]
          }
        }
      end

    q_info = Tracking.collection.aggregate([
          { "$match": match_by },
          { "$group": 
            { "_id": group_by,
              "male_votes": {"$sum": {"$cond": [ { "$eq": [ "$actor_gender", "male" ] }, 1, 0 ]}},
              "female_votes": {"$sum": {"$cond": [ { "$eq": [ "$actor_gender", "female" ] }, 1, 0 ]}},
              "total_votes": { "$sum": 1 }
            }
          }
        ])
  end

  def group_by
    if @filter[:by] == 'geolocation' 
      ({ "country_code": "$country_code", "state_code": "$state_code", "state_name": "$state_name" })
    elsif @filter[:by] == 'zipcode'
      ({ "country_code": "$country_code", "state_code": "$state_code", "state_name": "$state_name", "city": "$city", "zipcode": "$postal_code" })
    else
      ({ "day": {"$dayOfMonth": "$created_at"}, "month": {"$month": "$created_at"}, "year": {"$year": "$created_at"} })
    end
  end

  def question_info
    match_by = if @filter[:offset]=="infinite"
        {
          "question_id": @filter[:q_id],
          "action": 'vote'
        }
      else
        {
          "question_id": @filter[:q_id],
          "action": 'vote',
          "created_at": { 
            "$gte":  @filter[:from_date],
            "$lte":  @filter[:to_date]
          }
        }
      end
    @q_info = Tracking.collection.aggregate([
          { "$match": match_by },
          { "$group": 
            { "_id": "null",
              "male_votes": {"$sum": {"$cond": [ { "$eq": [ "$actor_gender", "male" ] }, 1, 0 ]}},
              "female_votes": {"$sum": {"$cond": [ { "$eq": [ "$actor_gender", "female" ] }, 1, 0 ]}},
              "other_votes": {"$sum": {"$cond": [ { "$eq": [ "$actor_gender", "unknown" ] }, 1, 0 ]}},
              "total_votes": { "$sum": 1 },
              "top_voting_city": { "$max": "$city" },
              "top_voting_region": { "$max": "$state_name" },              
              "top_voting_zipcode": { "$max": "$postal_code" }
            }
          }
        ])
  end

  def self.celebrity_info questions
    celebs = {}
    user_ids = questions.collect(&:asked_to).flatten.uniq
    User.where(_id: {'$in': user_ids}).map do |u| 
      celebs[u.id.to_s] = {}
      celebs[u.id.to_s][:name] = u.name
      celebs[u.id.to_s][:username] = u.username
    end
    celebs
  end

  private

  def asked_to_length
    @filter[:debate] == 0 ? "< 2" : @filter[:debate] == 1 ? "> 1" : "> 0"
  end

  def sanitize key
    case key
    when :entity
      %w(questions votes).include?(@filter[key].to_s) ? @filter[key].to_s : 'questions'
    when :by
      %w(date geolocation zipcode).include?(@filter[key].to_s) ? @filter[key].to_s : 'date'
    when :offset
      if @filter[:questions_only]
        ( @filter[key].present? && %w(0 7 14 30 60 90).include?(@filter[key]) ? @filter[key].to_i : @filter[key]=='infinite' ? 'infinite' : 7 ) rescue 7
      else
        ( @filter[key].present? && (1..30).include?(@filter[key].to_i ) ? @filter[key].to_i : 30 ) rescue 30
      end
    when :answered
      %w(0 1).include?(@filter[key]) ? @filter[key].to_i : nil
    when :debate
      %w(0 1).include?(@filter[key]) ? @filter[key].to_i : nil
    when :gender
      %w(male female).include?(@filter[key].to_s) ? @filter[key].to_s : nil
    when :page
      @filter[key] == 0 ? 1 : @filter[key].is_a?(Integer) ? @filter[key].to_i : 1
    when :sort_by
      %w(city_asc city_desc date_desc date_asc vote_desc vote_asc last_vote_desc last_vote_asc sentmnt_asc sentmnt_desc).include?(@filter[key].to_s) ? sort_by_value(@filter[key]) : 'created_at DESC'
    when :sentiment_from
      %w(0 1 2 3 4).include?(@filter[key]) ? @filter[key].to_i : 0
    when :sentiment_to
      %w(0 1 2 3 4).include?(@filter[key]) ? @filter[key].to_i : 4
    end
  end

  def setDefault
    @filter[:entity]          = sanitize :entity
    @filter[:by]              = sanitize :by
    @filter[:offset]          = sanitize :offset

    @filter[:answered]        = sanitize :answered
    @filter[:debate]          = sanitize :debate
    @filter[:gender]          = sanitize :gender
    @filter[:sort_by]         = sanitize :sort_by

    @filter[:sentiment_from]  = sanitize :sentiment_from
    @filter[:sentiment_to]    = sanitize :sentiment_to

    @filter[:page]            = sanitize :page

    if @filter[:questions_only]
      unless @filter[:offset] == 'infinite'
        @filter[:from_date]   = Date.today.to_date - @filter[:offset].to_i.days
        @filter[:to_date]     = Date.today.to_date + 1.day
      end
    else
      @filter[:to_date]     = ( DateTime.strptime(@filter[:to_date], '%b %e, %Y') rescue Date.today.to_date ) + 1.day
      @filter[:from_date]   = @filter[:to_date] - @filter[:offset]
    end
  end

  def sort_by_value key
    sort = key.split('_')
    sort_by = case sort[0]
      when 'city'
        'city ' + sort[1].upcase
      when 'date'
        'created_at ' + sort[1].upcase
      when 'vote'
        'requestor_count ' + sort[1].upcase
      when 'last_vote'
        'last_vote_at ' + sort[1].upcase
      when 'sentmnt'
        'sentiment ' + sort[1].upcase
      end
    sort_by
  end
end
