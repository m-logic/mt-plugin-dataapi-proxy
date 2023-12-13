package MT::App::DataAPIProxy;

use strict;
use base 'MT::App::DataAPI';

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

sub dataapi {
    my $app = shift;

    my $mtapp = MT::App->new;
    # ensure session_credentials
    $mtapp->user(undef);
    delete $mtapp->{cookies}; 
    #
    my ($author) = $mtapp->login;
    my ($mtsession) = $mtapp->session;
    my $access_token;
    my $session;
    if ($author && $mtsession) {
        if ( MT->version_number < 7 || $author->can_sign_in_data_api ) {
            if (DEBUG) {
                MT->log( 'DataAPIProxy: user:' . $author->name );
            }
            my $session_id = $mtsession->get('dataapiproxy_session');
            my $session_created = 0;
            if ($session_id) {
                $app->session_user( $author, $session_id );
            }
            if (!$app->{session}) {
                $app->start_session( $author, 0 );
                $session_created = 1;
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
                    MT->log( 'created dataapi session:' . $session_id );
                }
                else {
                    MT->log( 'load dataapi session:' . $session_id );
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
                    MT->log( 'created accesstoken:' . $access_token->id );
                }
                else {
                    MT->log( 're-use accesstoken:' . $access_token->id );
                }
            }
            $ENV{HTTP_X_MT_AUTHORIZATION} = 'MTAuth accessToken=' . $access_token->id;
        }
        else {
            if (DEBUG) {
                MT->log('DataAPIProxy: api access prohibited');
            }
        }
    }
    else {
        if (DEBUG) {
            MT->log('DataAPIProxy: anonymous user access');
        }
    }

    my $clientId = $app->param('clientId') || 'DataAPIProxy';
    $app->request( 'data_api_current_client_id', $clientId );
    my $result = $app->api(@_);
    my $endpoint_id = ( $app->current_endpoint || {} )->{id} || '';
    if (DEBUG) {
        MT->log( 'endpoint: ' . $endpoint_id );
    }
    $mtapp->takedown();

    return $result;
}

1;
