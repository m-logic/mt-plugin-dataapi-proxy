package MT::Plugin::DataAPIProxy;

use strict;
use MT;
use MT::Plugin;

@MT::Plugin::DataAPIProxy::ISA = qw(MT::Plugin);

=pod
ex)
mt-data-api.cgi/v2/sites/1/entries?search=test
 ->
dataapiproxy.cgi/v2/sites/1/entries?search=test
=cut

my $PLUGIN_NAME = 'DataAPIProxy';
my $VERSION = '0.9';
my $plugin = new MT::Plugin::DataAPIProxy({
    name => $PLUGIN_NAME,
    version => $VERSION,
    author_name => 'M-Logic, Inc.',
    author_link => 'http://m-logic.co.jp/',
    registry => {
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
    },
});

if (MT->version_number >= 6) { # required MT6
    MT->add_plugin($plugin);
}

sub instance { $plugin; }

1;
