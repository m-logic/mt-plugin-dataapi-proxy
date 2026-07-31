package MT::DataAPI::Endpoint::DataAPIProxy::Search;

use strict;
use warnings;

use MT::App::Search;
use MT::App::Search::ContentData;

sub search {
    my ( $app, $endpoint ) = @_;

    return _content_data_search(@_)
      if $endpoint->{version} >= 4 && $app->param('cdSearch');
    return _entry_or_tag_search(@_);
}

sub _entry_or_tag_search {
    my ( $app, $endpoint ) = @_;

    my $tag_search = $app->param('tagSearch') ? 1 : 0;
    local $app->{mode} = $tag_search ? 'tag' : 'default';

    my $search =
        $tag_search
      ? $app->param('tag') || $app->param('search')
      : $app->param('search');
    if ( !( defined $search && $search ne '' ) ) {
        return $app->error(
            $app->translate(
                'A parameter "[_1]" is required.',
                ( $tag_search ? 'tag' : 'search' )
            ),
            400
        );
    }

    my $search_class = 'MT::App::Search';
    if ( $app->param('freeText')
        && eval { require MT::App::Search::FreeText; 1 } )
    {
        $search_class = 'MT::App::Search::FreeText';
    }
    local @MT::App::DataAPI::ISA = ($search_class);

    MT::App::Search::init_request($app);
    return $app->error( $app->errstr, 400 ) if $app->errstr;
    return unless _data_api_search_is_enabled($app);

    $app->param( 'format', 'data_api' );
    require MT::DataAPI::Endpoint::v2::Search;
    no warnings 'once';
    local *MT::App::Search::renderdata_api =
      \&MT::DataAPI::Endpoint::v2::Search::_renderdata_api;

    my $result;
    if ($tag_search) {
        require MT::App::Search::TagSearch;
        $result = MT::App::Search::TagSearch::process($app);
    }
    else {
        $result = MT::App::Search::process($app);
    }

    MT::App::Search::takedown($app);
    return unless $result;

    $app->send_http_header( $app->current_format->{mime_type} );
    $app->{no_print_body} = 1;
    $app->print_encode($result);
    return;
}

sub _content_data_search {
    my ( $app, $endpoint ) = @_;

    my $search = $app->param('search');
    return $app->error(
        $app->translate( 'A parameter "[_1]" is required.', 'search' ) )
      unless defined $search && $search ne '';

    local $app->{mode} = 'default';
    local @MT::App::DataAPI::ISA = ('MT::App::Search::ContentData');

    $app->init_request;
    return $app->error( $app->errstr, 400 ) if $app->errstr;
    return unless _data_api_search_is_enabled($app);

    $app->param( 'format', 'data_api' );
    require MT::DataAPI::Endpoint::v2::Search;
    no warnings 'once';
    local *MT::App::Search::ContentData::renderdata_api =
      \&MT::DataAPI::Endpoint::v2::Search::_renderdata_api;

    my $result = $app->process;
    $app->takedown;
    return unless $result;

    $app->send_http_header( $app->current_format->{mime_type} );
    $app->{no_print_body} = 1;
    $app->print_encode($result);
    return;
}

sub _data_api_search_is_enabled {
    my ($app) = @_;

    return 1
      if $app->user
      && $app->user->is_superuser
      && !$app->config->SuperuserRespectsDataAPIDisableSite;

    my @blog_term;
    my $include_blogs = $app->{searchparam}{IncludeBlogs};
    push @blog_term, { id    => $include_blogs } if $include_blogs;
    push @blog_term, { class => '*' } unless @blog_term;

    my @sites = $app->model('blog')->load(@blog_term);
    require MT::CMS::Blog;
    for my $site (@sites) {
        unless ( MT::CMS::Blog::data_api_is_enabled( $app, $site->id, $site ) )
        {
            return $app->error( 'Forbidden', 403 );
        }
    }
    return 1;
}

1;
