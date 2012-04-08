# vim: set ts=4 sts=4 sw=4 expandtab smarttab:
#
# This file is part of Pod-Markdown
#
# This software is copyright (c) 2004 by Marcel Gruenauer.
#
# This is free software; you can redistribute it and/or modify it under
# the same terms as the Perl 5 programming language system itself.
#
use 5.008;
use strict;
use warnings;

package Pod::Markdown;
{
  $Pod::Markdown::VERSION = '1.300000';
}
BEGIN {
  $Pod::Markdown::AUTHORITY = 'cpan:RWSTAUNER';
}
# ABSTRACT: Convert POD to Markdown
use parent qw(Pod::Parser);
use Pod::ParseLink (); # core

sub initialize {
    my $self = shift;
    $self->SUPER::initialize(@_);
    $self->_private;
    $self;
}

sub _private {
    my $self = shift;
    $self->{_MyParser} ||= {
        Text      => [],       # final text
        Indent    => 0,        # list indent levels counter
        ListType  => '-',      # character on every item
        searching => ''   ,    # what are we searching for? (title, author etc.)
        Title     => undef,    # page title
        Author    => undef,    # page author
    };
}

sub as_markdown {
    my ($parser, %args) = @_;
    my $data  = $parser->_private;
    my $lines = $data->{Text};
    my @header;
    if ($args{with_meta}) {
        @header = $parser->_build_markdown_head;
    }
    join("\n" x 2, @header, @{$lines});
}

sub _build_markdown_head {
    my $parser    = shift;
    my $data      = $parser->_private;
    return join "\n",
        map  { qq![[meta \l$_="$data->{$_}"]]! }
        grep { defined $data->{$_} }
        qw( Title Author );
}

sub _save {
    my ($parser, $text) = @_;
    my $data = $parser->_private;
    $text = $parser->_indent_text($text);
    push @{ $data->{Text} }, $text;
    return;
}

sub _unsave {
    my $parser = shift;
    my $data = $parser->_private;
    return pop @{ $data->{Text} };
}

sub _indent_text {
    my ($parser, $text) = @_;
    my $data   = $parser->_private;
    my $level  = $data->{Indent};
    my $indent = undef;
    if ($level > 0) {
        $level--;
    }
    $indent = ' ' x ($level * 4);
    my @lines = map { $indent . $_; } split(/\n/, $text);
    return wantarray ? @lines : join("\n", @lines);
}

sub _clean_text {
    my $text    = $_[1];
    my @trimmed = grep { $_; } split(/\n/, $text);

    return wantarray ? @trimmed : join("\n", @trimmed);
}

sub _escape {
    local $_ = $_[1];

    # do inline characters first
    s/([][\\`*_#])/\\$1/g;

    # escape unordered lists and blockquotes
    s/^([-+*>])/\\$1/mg;

    # escape dots that would wrongfully create numbered lists
    s/^( (?:>\s+)? \d+ ) (\.\x20)/$1\\$2/xgm;

    return $_;
}

sub command {
    my ($parser, $command, $paragraph, $line_num) = @_;
    my $data = $parser->_private;

    # cleaning the text
    $paragraph = $parser->_clean_text($paragraph);

    # is it a header ?
    if ($command =~ m{head(\d)}xms) {
        my $level = $1;

        $paragraph = $parser->_escape($paragraph);
        $paragraph = $parser->interpolate($paragraph, $line_num);

        # the headers never are indented
        $parser->_save($parser->format_header($level, $paragraph));
        if ($level == 1) {
            if ($paragraph =~ m{NAME}xmsi) {
                $data->{searching} = 'title';
            } elsif ($paragraph =~ m{AUTHOR}xmsi) {
                $data->{searching} = 'author';
            } else {
                $data->{searching} = '';
            }
        }
    }

    # opening a list ?
    elsif ($command =~ m{over}xms) {

        # update indent level
        $data->{Indent}++;

        # closing a list ?
    } elsif ($command =~ m{back}xms) {

        # decrement indent level
        $data->{Indent}--;
        $data->{searching} = '';
    } elsif ($command =~ m{item}xms) {
        $paragraph = $parser->interpolate($paragraph, $line_num);
        $paragraph =~ s{^[ \t]* \* [ \t]*}{}xms;

        if ($data->{searching} eq 'listpara') {
            $data->{searching} = 'listheadhuddled';
        }
        else {
            $data->{searching} = 'listhead';
        }

        if (length $paragraph) {
            $parser->textblock($paragraph, $line_num);
        }
    }

    # ignore other commands
    return;
}

sub verbatim {
    my ($parser, $paragraph) = @_;

    # NOTE: perlpodspec says parsers should expand tabs by default
    # NOTE: Apparently Pod::Parser does not.  should we?
    # NOTE: this might be s/^\t/" " x 8/e, but what about tabs inside the para?

    # POD verbatim can start with any number of spaces (or tabs)
    # markdown should be 4 spaces (or a tab)
    # so indent any paragraphs so that all lines start with at least 4 spaces
    my @lines = split /\n/, $paragraph;
    my $indent = ' ' x 4;
    foreach my $line ( @lines ){
        next unless $line =~ m/^( +)/;
        # find the smallest indentation
        $indent = $1 if length($1) < length($indent);
    }
    if( (my $smallest = length($indent)) < 4 ){
        # invert to get what needs to be prepended
        $indent = ' ' x (4 - $smallest);
        # leave tabs alone
        $paragraph = join "\n", map { /^\t/ ? $_ : $indent . $_ } @lines;
    }

    $parser->_save($paragraph);
}

sub _escape_non_code {
    my ($parser, $text, $ptree) = @_;
    $text = $parser->_escape($text)
        unless $ptree->isa('Pod::InteriorSequence') && $ptree->cmd_name eq 'C';
    return $text;
}

sub textblock {
    my ($parser, $paragraph, $line_num) = @_;
    my $data = $parser->_private;

    # escape markdown characters in text sequences except for inline code
    $paragraph = join '', $parser->parse_text(
        { -expand_text => '_escape_non_code' },
        $paragraph, $line_num
    )->raw_text;

    # interpolate the paragraph for embedded sequences
    $paragraph = $parser->interpolate($paragraph, $line_num);

    # clean the empty lines
    $paragraph = $parser->_clean_text($paragraph);

    # searching ?
    if ($data->{searching} =~ m{title|author}xms) {
        $data->{ ucfirst $data->{searching} } = $paragraph;
        $data->{searching} = '';
    } elsif ($data->{searching} =~ m{listhead(huddled)?$}xms) {
        my $is_huddled = $1;
        $paragraph = sprintf '%s %s', $data->{ListType}, $paragraph;
        if ($is_huddled) {
            $paragraph = $parser->_unsave() . "\n" . $paragraph;
        }
        $data->{searching} = 'listpara';
    } elsif ($data->{searching} eq 'listpara') {
        $data->{searching} = '';
    }

    # save the text
    $parser->_save($paragraph);
}

sub interior_sequence {
    my ($self, $seq_command, $seq_argument, $pod_seq) = @_;

    # nested links are not allowed
    return sprintf '%s<%s>', $seq_command, $seq_argument
        if $seq_command eq 'L' && $self->_private->{InsideLink};

    my $i = 2;
    my %interiors = (
        'I' => sub { return '_'  . $_[$i] . '_'  },      # italic
        'B' => sub { return '__' . $_[$i] . '__' },      # bold
        'C' => sub { return '`'  . $_[$i] . '`'  },      # monospace
        'F' => sub { return '`'  . $_[$i] . '`'  },      # system path
        # non-breaking space
        'S' => sub {
            (my $s = $_[$i]) =~ s/ /&nbsp;/g;
            return $s;
        },
        'E' => sub {
            my $charname = $_[$i];
            return '<' if $charname eq 'lt';
            return '>' if $charname eq 'gt';
            return '|' if $charname eq 'verbar';
            return '/' if $charname eq 'sol';

            # convert legacy charnames to more modern ones (see perlpodspec)
            $charname =~ s/\A([lr])chevron\z/${1}aquo/;

            return "&#$1;" if $charname =~ /^0(x[0-9a-fA-Z]+)$/;

            $charname = oct($charname) if $charname =~ /^0\d+$/;

            return "&#$charname;"      if $charname =~ /^\d+$/;

            return "&$charname;";
        },
        'L' => \&_resolv_link,
        'X' => sub { '' },
        'Z' => sub { '' },
    );
    if (exists $interiors{$seq_command}) {
        my $code = $interiors{$seq_command};
        return $code->($self, $seq_command, $seq_argument, $pod_seq);
    } else {
        return sprintf '%s<%s>', $seq_command, $seq_argument;
    }
}

sub _resolv_link {
    my ($self, $cmd, $arg) = @_;

    local $self->_private->{InsideLink} = 1;

    my ($text, $inferred, $name, $section, $type) =
      # perlpodspec says formatting codes can occur in all parts of an L<>
      map { $_ && $self->interpolate($_, 1) }
      Pod::ParseLink::parselink($arg);
    my $url = '';

    # TODO: make url prefixes configurable

    if ($type eq 'url') {
        $url = $name;
    } elsif ($type eq 'man') {
        # stolen from Pod::Simple::(X)HTML
        my ($page, $part) = $name =~ /\A([^(]+)(?:[(](\S*)[)])?/;
        $url = 'http://man.he.net/man' . ($part || 1) . '/' . ($page || $name);
    } else {
        if ($name) {
            $url = 'http://search.cpan.org/perldoc?' . $name;
        }
        if ($section){
            # TODO: sites/pod formatters differ on how to transform the section
            # TODO: we could do it according to specified url prefix or pod formatter
            # TODO: or allow a coderef?
            # TODO: (Pod::Simple::XHTML:idify() for metacpan)
            # TODO: (Pod::Simple::HTML section_escape/unicode_escape_url/section_url_escape for s.c.o.)
            $url .= '#' . $section;
        }
    }

    # if we don't know how to handle the url just print the pod back out
    if (!$url) {
        return sprintf '%s<%s>', $cmd, $arg;
    }

    return sprintf '[%s](%s)', ($text || $inferred), $url;
}

sub format_header {
    my ($level, $paragraph) = @_[1,2];
    sprintf '%s %s', '#' x $level, $paragraph;
}

1;


__END__
=pod

=for :stopwords Marcel Gruenauer Victor Moral Ryan C. Thompson <rct at thompsonclan d0t
org> Aristotle Pagaltzis Randy Stauner ACKNOWLEDGEMENTS textblock cpan
testmatrix url annocpan anno bugtracker rt cpants kwalitee diff irc mailto
metadata placeholders metacpan

=encoding utf-8

=head1 NAME

Pod::Markdown - Convert POD to Markdown

=head1 VERSION

version 1.300000

=head1 SYNOPSIS

    my $parser = Pod::Markdown->new;
    $parser->parse_from_filehandle(\*STDIN);
    print $parser->as_markdown;

=head1 DESCRIPTION

This module subclasses L<Pod::Parser> and converts POD to Markdown.

Literal characters in Pod that are special in Markdown
(like *asterisks*) are backslash-escaped
(except those in verbatim blocks or C<< CE<lt>codeE<gt> >> sections).

=head1 METHODS

=head2 initialize

Initializes a newly constructed object.

=head2 as_markdown

Returns the parsed POD as Markdown. Takes named arguments. If the C<with_meta>
argument is given a positive value, meta tags are generated as well.

=head2 command

Handles POD command paragraphs, denoted by a line beginning with C<=>.

=head2 verbatim

Handles verbatim text.

=head2 textblock

Handles normal blocks of POD.

=head2 interior_sequence

Handles interior sequences in POD. An interior sequence is an embedded command
within a block of text which appears as a command name - usually a single
uppercase character - followed immediately by a string of text which is
enclosed in angle brackets.

=head2 format_header

Formats a header according to the given level.

=head1 SUPPORT

=head2 Perldoc

You can find documentation for this module with the perldoc command.

  perldoc Pod::Markdown

=head2 Websites

The following websites have more information about this module, and may be of help to you. As always,
in addition to those websites please use your favorite search engine to discover more resources.

=over 4

=item *

Search CPAN

The default CPAN search engine, useful to view POD in HTML format.

L<http://search.cpan.org/dist/Pod-Markdown>

=item *

RT: CPAN's Bug Tracker

The RT ( Request Tracker ) website is the default bug/issue tracking system for CPAN.

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Pod-Markdown>

=item *

CPAN Ratings

The CPAN Ratings is a website that allows community ratings and reviews of Perl modules.

L<http://cpanratings.perl.org/d/Pod-Markdown>

=item *

CPAN Testers

The CPAN Testers is a network of smokers who run automated tests on uploaded CPAN distributions.

L<http://www.cpantesters.org/distro/P/Pod-Markdown>

=item *

CPAN Testers Matrix

The CPAN Testers Matrix is a website that provides a visual overview of the test results for a distribution on various Perls/platforms.

L<http://matrix.cpantesters.org/?dist=Pod-Markdown>

=item *

CPAN Testers Dependencies

The CPAN Testers Dependencies is a website that shows a chart of the test results of all dependencies for a distribution.

L<http://deps.cpantesters.org/?module=Pod::Markdown>

=back

=head2 Bugs / Feature Requests

Please report any bugs or feature requests by email to C<bug-pod-markdown at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Pod-Markdown>. You will be automatically notified of any
progress on the request by the system.

=head2 Source Code


L<https://github.com/rwstauner/Pod-Markdown>

  git clone https://github.com/rwstauner/Pod-Markdown.git

=head1 AUTHORS

=over 4

=item *

Marcel Gruenauer <marcel@cpan.org>

=item *

Victor Moral <victor@taquiones.net>

=item *

Ryan C. Thompson <rct at thompsonclan d0t org>

=item *

Aristotle Pagaltzis <pagaltzis@gmx.de>

=item *

Randy Stauner <rwstauner@cpan.org>

=back

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2004 by Marcel Gruenauer.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut

