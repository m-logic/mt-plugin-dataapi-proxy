package MT::App::DataAPIProxy;

use strict;
use base 'MT::App::DataAPI';

use MT::App;
use constant DEBUG => 0;

sub id {'dataapiproxy'}

sub init {
    my $app = shift;
    $app->SUPER::init(@_) or return;
    $app->add_methods( dataapi => \&dataapi, );
    $app->{template_dir} = 'data_api';
    $app->{default_mode} = 'dataapi';
    $app;
}

sub user_cookie {
    'mt_user';
}

sub session_user {
    MT::App::session_user(@_);
}

sub dataapi {
    my $app = shift;

    my ($author) = MT::App::login($app);
    my ($mtsession) = MT::App::session($app);
    # ensure no session for DataAPI
    delete $app->{session};
    my $access_token;
    my $session;
    if (DEBUG) {
        require MT::Util::Log; MT::Util::Log->init();
    }
    if ($author && $mtsession) {
        if ( MT->version_number < 7 || $author->can_sign_in_data_api ) {
            MT::Util::Log->info( 'DataAPIProxy: user:' . $author->name ) if DEBUG;
            my $session_id = $mtsession->get('dataapiproxy_session');
            my $session_created = 0;
            if ($session_id) {
                if (!MT::App::DataAPI::session_user( $app, $author, $session_id )) {
                    MT::Util::Log->info( 'MT::App::DataAPI::session_user failed. session_id=' . $session_id) if DEBUG;
                    $session_id = undef;
                }
            }
            if (!$session_id) {
                MT::Util::Log->info( 'DataAPIProxy: no dataapiproxy_session. start_session') if DEBUG;
                MT::App::DataAPI::start_session( $app, $author, 0 );
                $session_created = 1;
                if (DEBUG) {
                    MT::Util::Log->info( 'MT::App::DataAPI::start_session failed') unless $app->{session};
                }
            }
            $session = $app->{session}
                or return $app->error( 'Invalid login', 401 );
            $session_id = $session->id;
            if ($session_created) {
                $mtsession->set('dataapiproxy_session', $session_id );
                $mtsession->save;
            }
            if (DEBUG) {
                if ($session_created) {
                    MT::Util::Log->info( 'created dataapi session:' . $session_id );
                }
                else {
                    MT::Util::Log->info( 'load dataapi session:' . $session_id );
                }
            }
            my $access_token_created = 0;
            $access_token = $app->model('accesstoken')->load({session_id => $session_id});
            if (!$access_token) {
                my $token_id = $app->make_magic_token;
                $access_token = $app->model('accesstoken')->new;
                $access_token->id($token_id);
            }
            $access_token->set_values({
                session_id => $session_id,
                start => time,
            });
            $access_token->save;
            if (DEBUG) {
                if ($access_token_created) {
                    MT::Util::Log->info( 'created accesstoken:' . $access_token->id );
                }
                else {
                    MT::Util::Log->info( 're-use accesstoken:' . $access_token->id );
                }
            }
            $ENV{HTTP_X_MT_AUTHORIZATION} = 'MTAuth accessToken=' . $access_token->id;
        }
        else {
            MT::Util::Log->info('DataAPIProxy: api access prohibited') if DEBUG;
        }
    }
    else {
        MT::Util::Log->info('DataAPIProxy: anonymous user access') if DEBUG;
    }

    my $clientId = $app->param('clientId') || 'DataAPIProxy';
    $app->request( 'data_api_current_client_id', $clientId );
    my $result = $app->api(@_);
    my $endpoint_id = ( $app->current_endpoint || {} )->{id} || '';
    MT::Util::Log->info( 'endpoint: ' . $endpoint_id ) if DEBUG;
    MT::App::takedown($app);
    return $result;
}

1;
