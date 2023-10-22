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
my $VERSION = '0.95';
my $plugin = new MT::Plugin::DataAPIProxy({
    name => $PLUGIN_NAME,
    version => $VERSION,
    author_name => 'M-Logic, Inc.',
    author_link => 'http://m-logic.co.jp/',
});

my $saved_init_plugins;
my $is_data_api_initialized = 0;
if (MT->version_number >= 6) { # required MT6
    require MT::App::DataAPI;
    no warnings 'once';
    no warnings 'redefine';
    $saved_init_plugins = \&MT::App::DataAPI::init_plugins;
    *MT::App::DataAPI::init_plugins = sub {
        return 1 if MT->version_number < 8 && $_[0]->id eq 'dataapiproxy';
        # hack to avoid double initialization...
        return 1 if $is_data_api_initialized;
        $is_data_api_initialized = 1;
        &$saved_init_plugins(@_);
    };
    MT->add_plugin($plugin);
}

sub instance { $plugin; }

sub init_registry {
    my $plugin = shift;
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
            },
        },
    });
}

1;
