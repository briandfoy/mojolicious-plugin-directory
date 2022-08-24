use v5.20;

package Mojolicious::Plugin::Directory;
use strict;
use warnings;
use experimental qw(signatures);

our $VERSION = '0.14';

use Cwd ();
use Encode ();
use DirHandle;
use Mojo::Base qw{ Mojolicious::Plugin -signatures };
use Mojolicious::Types;
use Mojo::JSON qw(encode_json);

# Stolen from Plack::App::Direcotry
my $default_dir_page = <<'PAGE';
<html><head>
  <title>Index of <%= $cur_path %></title>
  <meta http-equiv="content-type" content="text/html; charset=utf-8" />
  <style type='text/css'>
table { width:100%%; }
.name { text-align:left; }
.size, .mtime { text-align:right; }
.type { width:11em; }
.mtime { width:15em; }
  </style>
</head><body>
<h1>Index of <%= $cur_path %></h1>
<hr />
<table>
  <tr>
    <th class='name'>Name</th>
    <th class='size'>Size</th>
    <th class='type'>Type</th>
    <th class='mtime'>Last Modified</th>
  </tr>
  % for my $file (@$files) {
  <tr>
    <td class='name'><a href='<%= $file->{url} %>'><%== $file->{name} %></a></td>
    <td class='size'><%= $file->{size} %></td><td class='type'><%= $file->{type} %></td>
    <td class='mtime'><%= $file->{mtime} %></td>
  </tr>
  % }
</table>
<hr />
</body></html>
PAGE

sub register ( $self, $app, $args ) {
	$args->{auto_index} //= 1;
	$args->{dir_page}   //= $default_dir_page;
	$args->{root}       //= Cwd::getcwd;

	$args->{root}     = Mojo::File->new($args->{root});

	foreach my $key ( qw(auto_index dir_index dir_page handler json root) ) {
		$app->helper( $key => sub { $args->{$key} } );
		}

	my $serve_single_file = -f $app->root->to_abs;
	if( $serve_single_file ) {
		@{$app->static->paths} = ();
		$app->static->extra({ $app->root => $app->root->to_abs });
		}
	else {
		@{$app->static->paths} = $app->root->to_abs;
		}

	@{$app->static->paths} = $serve_single_file ? () : $app->root;
	$app->log->debug( "Static paths are <@{$app->static->paths}>" );

    my $sub = $serve_single_file ? \&serve_single_file : \&serve_directory;
    $app->hook( before_dispatch => $sub );

    return $app;
	}

# We don't care what the request path is; we will always serve $c->root
sub serve_single_file ( $c ) {
	render_file( $c, $c->root, $c->handler )
	}

sub serve_directory ( $c ) {
	# can't just remove trailing slash because that screws around with
	# redirects in some way I don't understand.
	my $path = $c->root->child( Mojo::Util::url_unescape( $c->req->url->path ) )->to_rel;

	if ( -f $path ) {
		render_file( $c, $path, $c->handler );
		}
	elsif ( -d $path ) {
		if( $c->dir_index && ( my $index_path = locate_index( $c->dir_index, $path ) ) ) {
			return render_file( $c, $index_path, $c->handler );
			}

		if( $c->req->url->path ne '/' && ! $c->req->url->path->trailing_slash ) {
			$c->redirect_to($c->req->url->path->trailing_slash(1));
			return;
			}

		if( $c->auto_index ) {
			render_indexes( $c, $path, $c->json );
			}
		else {
			$c->reply->not_found;
			}
		}
	}

sub locate_index ( $index, $dir = Cwd::getcwd ) {
    return unless $index;
    my $root  = Mojo::File->new( $dir );
    $index = ( ref $index eq 'ARRAY' ) ? $index : [$index];
    for (@$index) {
        my $path = $root->child($_);
        return $_ if -e $path;
    }
}

sub render_file ( $c, $path, $handler ) {
    $handler->( $c, $path ) if ref $handler eq 'CODE';
    return if $c->tx->res->code;
    $c->stash( path => $path );
    $c->reply->static($path);
}

sub render_indexes ( $c, $dir, $json ) {
    my @files =
        ( $c->req->url->path eq '/' )
        ? ()
        : ( { url => '../', name => 'Parent Directory', size => '', type => '', mtime => '' } );
    my $children = list_files($dir);

    my $cur_path = Encode::decode_utf8( Mojo::Util::url_unescape( $c->req->url->path ) );
    for my $basename ( sort { $a cmp $b } @$children ) {
    	state $types = Mojolicious::Types->new;

        my $file = "$dir/$basename";
        my $url  = Mojo::Path->new($cur_path)->trailing_slash(0);
        push @{ $url->parts }, $basename;

        my $is_dir = -d $file;
        my @stat   = stat _;
        if ($is_dir) {
            $basename .= '/';
            $url->trailing_slash(1);
        }

        my $mime_type =
            $is_dir
            ? 'directory'
            : ( $types->type( get_ext($file) || 'txt' ) || 'text/plain' );
        my $mtime = Mojo::Date->new( $stat[9] )->to_string();

        push @files, {
            url   => $url,
            name  => $basename,
            size  => $stat[7] || 0,
            type  => $mime_type,
            mtime => $mtime,
        };
    }

    my $any = { inline => $c->dir_page, files => \@files, cur_path => $cur_path };
    if ($json) {
        $c->respond_to(
            json => { json => encode_json(\@files) },
            any  => $any,
        );
    }
    else {
        $c->render( %$any );
    }
}

sub get_ext ( $file ) {
    $file =~ /\.([0-9a-zA-Z]+)$/ || return;
    return lc $1;
}

sub list_files ( $dir ) {
    return [] unless $dir;
    my $dh = DirHandle->new($dir);
    my @children;
    while ( defined( my $ent = $dh->read ) ) {
        next if $ent eq '.' or $ent eq '..';
        push @children, Encode::decode_utf8($ent);
    }
    return [ @children ];
}

1;

__END__

=encoding utf8

=head1 NAME

Mojolicious::Plugin::Directory - Serve static files from document root with directory index

=head1 SYNOPSIS

  # simple usage
  use Mojolicious::Lite;
  plugin( 'Directory', root => "/path/to/htdocs" )->start;

  # with handler
  use Text::Markdown qw{ markdown };
  use Path::Class;
  use Encode qw{ decode_utf8 };
  plugin('Directory', root => "/path/to/htdocs", handler => sub {
      my ($c, $path) = @_;
      if ( -f $path && $path =~ /\.(md|mkdn)$/ ) {
          my $text = file($path)->slurp;
          my $html = markdown( decode_utf8($text) );
          $c->render( inline => $html );
      }
  })->start;

  or

  > perl -Mojo -E 'a->plugin("Directory", root => "/path/to/htdocs")->start' daemon

=head1 DESCRIPTION

L<Mojolicious::Plugin::Directory> is a static file server directory index a la Apache's mod_autoindex.

=head1 METHODS

L<Mojolicious::Plugin::Directory> inherits all methods from L<Mojolicious::Plugin>.

=head1 OPTIONS

L<Mojolicious::Plugin::Directory> supports the following options.

=head2 C<root>

  # Mojolicious::Lite
  plugin Directory => { root => "/path/to/htdocs" };

Document root directory. Defaults to the current directory.

If root is a file, serve only root file.

=head2 C<auto_index>

   # Mojolicious::Lite
   plugin Directory => { auto_index => 0 };

Automatically generate index page for directory, default true.

=head2 C<dir_index>

  # Mojolicious::Lite
  plugin Directory => { dir_index => [qw/index.html index.htm/] };

Like a Apache's DirectoryIndex directive.

=head2 C<dir_page>

  # Mojolicious::Lite
  plugin Directory => { dir_page => $template_str };

a HTML template of index page

=head2 C<handler>

  # Mojolicious::Lite
  use Text::Markdown qw{ markdown };
  use Path::Class;
  use Encode qw{ decode_utf8 };
  plugin Directory => {
      handler => sub {
          my ($c, $path) = @_;
          if ($path =~ /\.(md|mkdn)$/) {
              my $text = file($path)->slurp;
              my $html = markdown( decode_utf8($text) );
              $c->render( inline => $html );
          }
      }
  };

CODEREF for handle a request file.

If not rendered in CODEREF, serve as static file.

=head2 C<json>

  # Mojolicious::Lite
  # /dir (Accept: application/json)
  # /dir?_format=json
  plugin Directory => { json => 1 };

Enable json response.

=head1 AUTHOR

hayajo E<lt>hayajo@cpan.orgE<gt>

=head1 CONTRIBUTORS

Many thanks to the contributors for their work.

=over 4

=item ChinaXing

=back

=head1 SEE ALSO

L<Plack::App::Directory>

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
