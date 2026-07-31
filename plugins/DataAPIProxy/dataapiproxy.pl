package MT::Plugin::DataAPIProxy;

use strict;
use MT;
use MT::App;
use MT::Plugin;

use base qw( MT::Plugin );

=pod
ex)
mt-data-api.cgi/v2/sites/1/entries?search=test
 ->
dataapiproxy.cgi/v2/sites/1/entries?search=test
=cut

my $PLUGIN_NAME = 'DataAPIProxy';
my $VERSION     = '1.1';
my $plugin      = new MT::Plugin::DataAPIProxy(
    {
        name        => $PLUGIN_NAME,
        version     => $VERSION,
        author_name => 'M-Logic, Inc.',
        author_link => 'http://m-logic.co.jp/',
    }
);

our $DataAPICoreRegistered = 0;

our %DataAPICoreAliases;

my $saved_init_plugins;
if ( MT->version_number >= 7 ) {

    if ( MT->instance && eval { MT->instance->id } eq 'data_api' ) {
        for ( my $i = 0 ; my @caller = caller($i) ; $i++ ) {
            next
              unless ( $caller[3] || '' ) eq 'MT::App::DataAPI::init_plugins';
            $DataAPICoreRegistered = 1;
            last;
        }
    }

    require MT::App::DataAPI;
    no warnings 'once';
    no warnings 'redefine';
    $saved_init_plugins             = \&MT::App::DataAPI::init_plugins;
    *MT::App::DataAPI::init_plugins = sub {
        my $app = shift;

        my $is_data_api = $app->id eq 'data_api';

        if ( $is_data_api && $DataAPICoreRegistered ) {
            my $register = \&MT::_register_core_callbacks;
            no warnings 'redefine';
            local *MT::_register_core_callbacks = sub {
                my ( $class, $table ) = @_;
                my %keep = map { $_ => $table->{$_} }
                  grep { !$DataAPICoreAliases{$_} } keys %$table;
                return 1 unless %keep;
                return $register->( $class, \%keep );
            };
            return &$saved_init_plugins( $app, @_ );
        }

        my $result = &$saved_init_plugins( $app, @_ );
        $DataAPICoreRegistered = 1 if $is_data_api;
        return $result;
    };
    MT->add_plugin($plugin);
}

sub instance { $plugin; }

sub init_registry {
    my $plugin = shift;
    require MT::DataAPI::Format;
    require MT::DataAPI::Resource;
    require MT::Import;
    $plugin->registry(
        {
            config_settings => {
                DataAPIProxyScript => {
                    default => 'dataapiproxy.cgi',
                },
            },
            applications => {
                dataapiproxy => {
                    handler   => 'MT::App::DataAPIProxy',
                    script    => sub { MT->config->DataAPIProxyScript },
                    methods   => sub { MT->app->core_methods() },
                    endpoints => sub { MT->app->core_endpoints() },
                    resources =>
                      sub { MT::DataAPI::Resource->core_resources() },
                    formats => sub { MT::DataAPI::Format->core_formats() },
                    default_format => 'json',
                    query_builder  =>
                      '$Core::MT::DataAPI::Endpoint::Common::query_builder',
                    default        => sub { MT->app->core_parameters() },
                    import_formats => sub { MT::Import->core_import_formats() },
                },
            },
        }
    );
}

1;
