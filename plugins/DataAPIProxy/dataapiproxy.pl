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
my $VERSION = '1.01';
my $plugin = new MT::Plugin::DataAPIProxy({
    name => $PLUGIN_NAME,
    version => $VERSION,
    author_name => 'M-Logic, Inc.',
    author_link => 'http://m-logic.co.jp/',
});

if (MT->version_number >= 7) { # required MT7
    MT->add_plugin($plugin);
}

sub instance { $plugin; }

sub init_registry {
    my $plugin = shift;
    require MT::DataAPI::Format;
    require MT::DataAPI::Resource;
    require MT::Import;
    $plugin->registry({
        config_settings => {
            DataAPIProxyScript => {
                default => 'dataapiproxy.cgi',
            },
        },
        applications => {
            dataapiproxy => {
                handler => 'MT::App::DataAPIProxy',
                script => sub { MT->config->DataAPIProxyScript },
                methods   => sub { MT->app->core_methods() },
                endpoints => sub { MT->app->core_endpoints() },
                resources => sub { MT::DataAPI::Resource->core_resources() },
                formats   => sub { MT::DataAPI::Format->core_formats() },
                default_format => 'json',
                query_builder =>
                    '$Core::MT::DataAPI::Endpoint::Common::query_builder',
                # This is for search endpoint.
                default        => sub { MT->app->core_parameters() },
                import_formats => sub { MT::Import->core_import_formats() },
            },
        },
    });
}

1;
