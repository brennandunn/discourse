# name: discourse-learn_auth
# about: learn.thoughtbot.com login support for Discourse
# version: 0.1
# authors: Chad Pytel, thoughtbot

require 'auth/oauth2_authenticator'

class LearnAuthenticator < ::Auth::OAuth2Authenticator
  def after_authenticate(auth_token)
    result = super
    populate_result_with_auth_info(result, auth_token)
    set_permissions(result.user, result.extra_data)
    result
  end

  def after_create_account(user, auth)
    set_permissions(user, auth[:extra_data])
    super
  end

  def register_middleware(omniauth)
    omniauth.provider :learn,
      ENV['MEMBERSHIP_OAUTH_CLIENT_ID_PRODUCTION'],
      ENV['MEMBERSHIP_OAUTH_CLIENT_SECRET_PRODUCTION']
  end

  private

  def populate_result_with_auth_info(result, auth_token)
    puts "TOKEN: #{auth_token.inspect}"
    result.name = auth_token[:info][:name]
    result.extra_data[:has_active_subscription] = auth_token[:info][:has_active_subscription]
    result.extra_data[:admin] = auth_token[:info][:admin]
    result.extra_data[:cohort] = auth_token[:info][:cohort]
  end

  def set_permissions(user, permissions)
    if user && user.persisted?
      set_admin_permission(user, permissions[:admin])
      # DISABLE IF SUBSCRIPTION INVALID

      # SYNC WITH COHORT
      permissions[:cohort].split(',').each do |cohort|
        add_to_cohort(user, cohort)
      end

      #set_subscription_permissions(user, permissions[:has_active_subscription])
    end
  end

  def add_to_cohort(user, cohort)
    if cohort.present?
      group = Group.lookup_group(cohort)
      if group and group.group_users.where(user_id: user.id).blank?
        group.add(user)
      end
    end
  end

  def set_admin_permission(user, admin)
    user.admin = admin
    user.save
  end

  def set_subscription_permissions(user, user_has_active_subscription)
    if(user_has_active_subscription)
      if not_in_subscriber_group?(user)
        subscriber_group.add(user)
      end
    else
      subscriber_group_user(user).destroy
    end
  end

  def not_in_subscriber_group?(user)
    subscriber_group_user(user).blank?
  end

  def subscriber_group_user(user)
    subscriber_group.group_users.where(user_id: user.id).first
  end

  def subscriber_group
    Group.lookup_group('Prime')
  end
end

require 'omniauth-oauth2'

class OmniAuth::Strategies::Learn < OmniAuth::Strategies::OAuth2
  LEARN_URL = ENV['LEARN_URL'] || 'http://localhost:3000'

  option :name, :learn

  option :client_options, {
    :site => LEARN_URL,
    :authorize_url => '/oauth/authorize'
  }

  uid { raw_info['id'] }

  info do
    raw_info.except('id')
  end

  def raw_info
    @raw_info ||= access_token.get('/api/v1/me.json').parsed
    @raw_info['user']
  end
end

auth_provider :title => 'Log in with your Account',
    :message => 'Log in with your Account',
    :frame_width => 920,
    :frame_height => 800,
    :authenticator => LearnAuthenticator.new('learn', trusted: true)

register_css <<CSS
.btn-social.learn {
  background: #b22115;
}
CSS
