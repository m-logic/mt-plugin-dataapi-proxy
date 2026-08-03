package MT::App::DataAPIProxy;

use strict;
use base 'MT::App::DataAPI';

use MT::App;
use MT::DataAPI::Endpoint::DataAPIProxy::Search;
use Scalar::Util qw( refaddr );
use constant DEBUG => 0;

sub id { 'dataapiproxy' }

our %Endpoints;

sub endpoints {
    my ( $app, $version ) = @_;

    return $app->SUPER::endpoints($version)
      unless $app->model('blog')->has_column('allow_data_api');
    $Endpoints{$version} ||= $app->_compile_proxy_endpoints($version);
}

sub _compile_proxy_endpoints {
    my ( $app, $version ) = @_;

    my $compiled = $app->SUPER::_compile_endpoints($version);
    my %endpoint_copy;
    for my $endpoint ( @{ $compiled->{list} } ) {
        my $copy = $endpoint;
        if ( $endpoint->{id} eq 'search' ) {
            $copy = {%$endpoint};
            delete $copy->{handler_ref};
            $copy->{handler} =
'$DataAPIProxy::MT::DataAPI::Endpoint::DataAPIProxy::Search::search';
        }
        $endpoint_copy{ refaddr($endpoint) } = $copy;
    }

    my $clone_tree;
    $clone_tree = sub {
        my ($node) = @_;
        return $node unless ref($node) eq 'HASH';
        my $address = refaddr($node);
        return $endpoint_copy{$address}
          if exists $endpoint_copy{$address};
        return { map { $_ => $clone_tree->( $node->{$_} ) } keys %$node };
    };

    return {
        hash => {
            map {
                my $endpoint = $compiled->{hash}{$_};
                $_ => $endpoint_copy{ refaddr($endpoint) }
            } keys %{ $compiled->{hash} }
        },
        tree => $clone_tree->( $compiled->{tree} ),
        list =>
          [ map { $endpoint_copy{ refaddr($_) } } @{ $compiled->{list} } ],
    };
}

sub init_plugins {
    my $app    = shift;
    my $result = $app->SUPER::init_plugins(@_);

    $MT::Plugin::DataAPIProxy::DataAPICoreRegistered = 1;
    return $result;
}

sub _register_core_callbacks {
    my ( $app, $table ) = @_;

    $app->SUPER::_register_core_callbacks($table) or return;

    return 1 if $MT::Plugin::DataAPIProxy::DataAPICoreRegistered;

    my $prefix = $app->id . '_';
    my %aliases;
    for my $name ( keys %$table ) {
        next unless $name =~ m/\A\Q$prefix\E/;
        ( my $alias = $name ) =~ s/\A\Q$prefix\E/data_api_/;
        $aliases{$alias} = $table->{$name};
    }
    return 1 unless %aliases;

    $app->SUPER::_register_core_callbacks( \%aliases ) or return;
    $MT::Plugin::DataAPIProxy::DataAPICoreAliases{$_} = 1 for keys %aliases;
    return 1;
}

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

sub _cms_session {
    my ($app) = @_;

    my %param_exists = map { $_ => 1 } $app->multi_param;
    my %credentials;
    for my $name (qw( username password )) {
        $credentials{$name} = [ $app->multi_param($name) ]
          if $param_exists{$name};
        $app->delete_param($name);
    }

    my ( $author, $mtsession, $error );
    {
        local $@;
        eval {
            ($author)    = MT::App::login($app);
            ($mtsession) = MT::App::session($app);
            1;
        } or $error = $@;
    }

    for my $name (qw( username password )) {
        $app->delete_param($name);
        $app->param( $name, @{ $credentials{$name} } )
          if $param_exists{$name};
    }

    die $error if defined $error;
    return ( $author, $mtsession );
}

sub dataapi {
    my $app = shift;

    return $app->error( 'DataAPIProxy plugin is not loaded.', 503 )
      unless MT::Plugin::DataAPIProxy->can('disable_anonymous_access');

    my ( $author, $mtsession ) = _cms_session($app);
    my $disable_anonymous_access =
      MT::Plugin::DataAPIProxy::disable_anonymous_access();
    delete $app->{session};
    my $access_token;
    my $session;
    if (DEBUG) {
        require MT::Util::Log;
        MT::Util::Log->init();
    }
    if ( $author && $mtsession ) {
        if ( MT->version_number < 7 || $author->can_sign_in_data_api ) {
            MT::Util::Log->info( 'DataAPIProxy: user:' . $author->name )
              if DEBUG;
            my $session_id      = $mtsession->get('dataapiproxy_session');
            my $session_created = 0;
            if ($session_id) {
                if (
                    !MT::App::DataAPI::session_user(
                        $app, $author, $session_id
                    )
                  )
                {
                    MT::Util::Log->info(
                        'MT::App::DataAPI::session_user failed. session_id='
                          . $session_id )
                      if DEBUG;
                    $session_id = undef;
                }
            }
            if ( !$session_id ) {
                MT::Util::Log->info(
                    'DataAPIProxy: no dataapiproxy_session. start_session')
                  if DEBUG;
                MT::App::DataAPI::start_session( $app, $author, 0 );
                $session_created = 1;
                if (DEBUG) {
                    MT::Util::Log->info(
                        'MT::App::DataAPI::start_session failed')
                      unless $app->{session};
                }
            }
            $session = $app->{session}
              or return $app->error( 'Invalid login', 401 );
            $session_id = $session->id;
            if ($session_created) {
                $mtsession->set( 'dataapiproxy_session', $session_id );
                $mtsession->save;
            }
            if (DEBUG) {
                if ($session_created) {
                    MT::Util::Log->info(
                        'created dataapi session:' . $session_id );
                }
                else {
                    MT::Util::Log->info(
                        'load dataapi session:' . $session_id );
                }
            }
            my $access_token_created = 0;
            $access_token =
              $app->model('accesstoken')->load( { session_id => $session_id } );
            if ( !$access_token ) {
                my $token_id = $app->make_magic_token;
                $access_token = $app->model('accesstoken')->new;
                $access_token->id($token_id);
            }
            $access_token->set_values(
                {
                    session_id => $session_id,
                    start      => time,
                }
            );
            $access_token->save;
            if (DEBUG) {
                if ($access_token_created) {
                    MT::Util::Log->info(
                        'created accesstoken:' . $access_token->id );
                }
                else {
                    MT::Util::Log->info(
                        're-use accesstoken:' . $access_token->id );
                }
            }
            $ENV{HTTP_X_MT_AUTHORIZATION} =
              'MTAuth accessToken=' . $access_token->id;
        }
        else {
            MT::Util::Log->info('DataAPIProxy: api access prohibited') if DEBUG;
            return $app->error( 'Forbidden', 403 )
              if $disable_anonymous_access;
        }
    }
    else {
        MT::Util::Log->info('DataAPIProxy: anonymous user access') if DEBUG;
        return $app->error( 'Forbidden', 403 )
          if $disable_anonymous_access;
    }

    my $clientId = $app->param('clientId') || 'DataAPIProxy';
    $app->request( 'data_api_current_client_id', $clientId );
    my $result      = $app->api(@_);
    my $endpoint_id = ( $app->current_endpoint || {} )->{id} || '';
    MT::Util::Log->info( 'endpoint: ' . $endpoint_id ) if DEBUG;

    return $result;
}

1;
