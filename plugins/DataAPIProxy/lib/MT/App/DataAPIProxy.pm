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
    my $access_token;
    my $session;
    if ($author) {
        if ( MT->version_number < 7 || $author->can_sign_in_data_api ) {
            if (DEBUG) {
                MT->log( 'DataAPIProxy: user:' . $author->name );
            }
            $app->start_session( $author, 0 );
            $session = $app->{session}
                or return $app->error( 'Invalid login', 401 );
            if (DEBUG) {
                MT->log( 'created temporary session:' . $session->id );
            }
            $access_token = $app->model('accesstoken')->new;
            $access_token->set_values({
                id => $app->make_magic_token,
                session_id => $session->id,
                start => time,
            });
            $access_token->save;
            if (DEBUG) {
                MT->log( 'created temporary token:' . $access_token->id ) if $access_token;
            }
            $ENV{HTTP_X_MT_AUTHORIZATION} = 'MTAuth accessToken=' . $access_token->id if $access_token;
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

    $app->request( 'data_api_current_client_id', 'DataAPIProxy' );
    my $result = $app->api(@_);
    my $endpoint_id = ( $app->current_endpoint || {} )->{id} || '';
    if (DEBUG) {
        MT->log( 'endpoint: ' . $endpoint_id );
    }
    if ($access_token) {
        MT::DataAPI::Endpoint::Auth::revoke_token($app);
        if (DEBUG) {
            MT->log('delete temporary token');
        }

        # leave session as-is if dataapi made another token.
        $session->remove unless $endpoint_id eq 'authenticate';
        if (DEBUG) {
            MT->log('delete temporary session') unless $endpoint_id eq 'authenticate';
        }
    }
    $mtapp->takedown();

    return $result;
}

1;
