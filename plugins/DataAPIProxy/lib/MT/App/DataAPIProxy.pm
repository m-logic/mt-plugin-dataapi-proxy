package MT::App::DataAPIProxy;

use strict;
use base 'MT::App::DataAPI';
use MT::DataAPI::Endpoint::Auth;

sub id {'dataapiproxy'}

sub init {
    my $app = shift;
    $app->SUPER::init(@_) or return;
    $app->add_methods(
        dataapi => \&dataapi,
    );
    $app->{default_mode} = 'dataapi';
    $app;
}

sub dataapi {
    my $app = shift;

    my $mtapp = MT::App->new;
    my ($author) = $mtapp->login;

    $app->request( 'data_api_current_client_id', 'DataAPIProxy' );
    $app->start_session($author, 0) if $author; # remember: 0

    my $auth = MT::DataAPI::Endpoint::Auth::authentication($app);
    $ENV{HTTP_X_MT_Authorization} = 'MTAuth accessToken=' . $auth->{accessToken}
        if ($auth && exists $auth->{accessToken});

    my $result = $app->api(@_);

    $mtapp->takedown();

    return $result;
}

1;
