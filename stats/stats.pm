# Copyright (C) 2010 Quentin Sculo <squentin@free.fr>
#
# This file is part of Gmusicbrowser.
# Gmusicbrowser is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3, as
# published by the Free Software Foundation

=gmbplugin STATS
name	Stats
title	Stats plugin
version	0.11
author  Øystein Tråsdahl (based on the Artistinfo plugin)
desc	Retrieves album-relevant information (review etc.) from allmusic.com.
=cut

# TODO:
# - Create local links in the review that can be used for contextmenus and filtering.
# - Consider searching google instead, or add google search if amg fails.

package GMB::Plugin::STATS;
use strict;
use warnings;
use utf8;
require $::HTTP_module;
use Gtk2::Gdk::Keysyms;
use base 'Gtk2::Box';
use base 'Gtk2::Dialog';
use constant
{	OPT	=> 'PLUGIN_STATS_',
};

::SetDefaultOptions(OPT,LengthTopList => 8,
);


my $statswidget =
{	class		=> __PACKAGE__,
	tabicon		=> 'plugin-stats',
	tabtitle	=> _"Stats",
	schange		=> \&song_changed,
	group		=> 'Play',
	autoadd_type	=> 'context page text',
};


sub Start {
	Layout::RegisterWidget(PluginStats => $statswidget);
}

sub Stop {
	Layout::RegisterWidget(PluginStats => undef);
}

sub prefbox {
	my $spin_toplist = ::NewPrefSpinButton(OPT.'LengthTopList', 1, 50, step=>1, page=>5, text1=>_"Length of top lists : ");
	return ::Vpack($spin_toplist);
}


sub new {
	my ($class,$options) = @_;
	my $self = bless(Gtk2::VBox->new(0,0), $class);
	$self->{$_} = $options->{$_} for qw/group/;
	my $fontsize = $self->style->font_desc;
	$self->{fontsize} = $fontsize->get_size() / Gtk2::Pango->scale;

	# For the review: a TextView in a ScrolledWindow in a HBox
	my $textview = Gtk2::TextView->new();
	$self->signal_connect(map => \&song_changed);
	$textview->set_cursor_visible(0);
	$textview->set_wrap_mode('word');
	$textview->set_pixels_above_lines(2);
	$textview->set_editable(0);
	$textview->set_left_margin(5);
	$textview->set_has_tooltip(1);
	my $sw = Gtk2::ScrolledWindow->new();
	$sw->add($textview);
	$sw->set_shadow_type('none');
	$sw->set_policy('automatic','automatic');
	my $infoview = Gtk2::HBox->new();
	$infoview->set_spacing(0);
	$infoview->pack_start($sw,1,1,0);
	$textview->show();

	# Pack it all into self (a VBox)
	$self->pack_start($infoview,1,1,0);
	$infoview->show();
	$self->signal_connect(destroy => sub {$_[0]->cancel()}); # FIXME: renewed problem: Can't locate object method "cancel" via package "Gtk2::VBox"

	$self->{buffer} = $textview->get_buffer();
	$self->{textview} = $textview;
	$self->{infoview} = $infoview;
	return $self;
}

sub song_changed {
	my ($widget,$tmp,$group,$force) = @_; # $tmp = ::GetSelID($self), but not always. So we don't use it. $group is also not used.
	my $self = ::find_ancestor($widget, __PACKAGE__);
	return unless $self->mapped();
	my $ID = ::GetSelID($self);
	return unless $ID;

	my $buffer = $self->{buffer};
	$buffer->set_text("");
	my $fontsize = $self->{fontsize};
	my $tag_h2 = $buffer->create_tag(undef, font=>$fontsize+1, weight=>Gtk2::Pango::PANGO_WEIGHT_BOLD);
	my $tag_b  = $buffer->create_tag(undef, weight=>Gtk2::Pango::PANGO_WEIGHT_BOLD);
	my $tag_i  = $buffer->create_tag(undef, style=>'italic');
	my $iter = $buffer->get_start_iter();

	for my $field (qw/artist genre year/) {
		$buffer->insert_with_tags($iter, _("Top ".$field."s\n"), $tag_b);
		my $fid = Songs::Get_gid($ID, $field);
		my $fields_count = Songs::BuildHash($field, $::Library);
		my $i = 1;
		for my $key (sort {$fields_count->{$b} <=> $fields_count->{$a}} keys(%$fields_count)) {
			if (grep {$_ eq $field} qw/artist genre/) {
				$buffer->insert($iter, "$i) ".Songs::Gid_to_Get($field,$key)." ($fields_count->{$key} tracks)\n");
			} else {
				$buffer->insert($iter, "$i) $key ($fields_count->{$key} tracks)\n");
			}
			last if ++$i > $::Options{OPT.'LengthTopList'};
		}
		$buffer->insert($iter, "\n");
	}

	for my $field (qw/artist genre year/) {
		$buffer->insert_with_tags($iter, "Favorite ".$field."s\n", $tag_b);
		my @aids = @{Songs::Get_all_gids($field)};
		my $tracks_by_artist = Songs::BuildHash($field, $::Library, undef, 'idlist');
		my $pcs = {};
		for my $a (@aids) {
			my $pc_by_tracks = Songs::BuildHash('playcount', $tracks_by_artist->{$a});
			my $sum = 0;
			while (my ($k,$v) = each %$pc_by_tracks) {
				$sum += $k * $v;
			}
			$pcs->{$a} = $sum;
		}
		my $i = 1;
		for my $key (sort {$pcs->{$b} <=> $pcs->{$a}} keys(%$pcs)) {
			if (grep {$_ eq $field} qw/artist genre/) {
				$buffer->insert($iter, "$i) ".Songs::Gid_to_Get($field,$key)." ($pcs->{$key} plays)\n");
			} else {
				$buffer->insert($iter, "$i) $key ($pcs->{$key} plays)\n");
			}
			last if ++$i > $::Options{OPT.'LengthTopList'};
		}
		$buffer->insert($iter, "\n");
	}

 	$buffer->set_modified(0);

	# my $gid = Songs::Get_gid($id, 'genre');
	# my @gids = @{Songs::Get_all_gids('genre')};
	# print "gid  = @$gid\n";
	# print "gids = @gids\n";
	# print "genres = ".Songs::Gid_to_Get('genre',$_)." (gid = $_)\n" for @gids;
	# my $genre  = Songs::Get($id,'genre');
	# my @genres = Songs::Get_list($id,'genre');
	# # my $ids = Filter->newadd(1,'title:s:'.$title, 'artist:s:'.$artist)->filter();
	# # my $ids = Filter->new('genre:ecount:'.$genre)->filter();
	# # print "   IDS = "; while (my ($k,$v) = each(%$a)) {print "$k => $v, "}; print "\n";
	# print "   IDS = "; 
	# print "$_=>$a->{$_}, " for (sort keys %$a); 
	# print "\n";

}

1

