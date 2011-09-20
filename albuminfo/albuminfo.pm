# Copyright (C) 2010 Quentin Sculo <squentin@free.fr>
#
# This file is part of Gmusicbrowser.
# Gmusicbrowser is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3, as
# published by the Free Software Foundation

=gmbplugin ALBUMINFO
name	Albuminfo
title	Albuminfo plugin
version	0.11
author  Øystein Tråsdahl (based on the Artistinfo plugin)
desc	Retrieves album-relevant information (review etc.) from allmusic.com.
=cut

# TODO:
# - Create local links in the review that can be used for contextmenus and filtering.
# - Notify the user if AMGs "Release date" differs from GMBs "year" tag.
# - Consider searching google instead, or add google search if amg fails.

package GMB::Plugin::ALBUMINFO;
use strict;
use warnings;
use utf8;
require $::HTTP_module;
use Gtk2::Gdk::Keysyms;
use base 'Gtk2::Box';
use base 'Gtk2::Dialog';
use constant
{	OPT	=> 'PLUGIN_ALBUMINFO_',
};

::SetDefaultOptions(OPT,PathFile  => "~/.config/gmusicbrowser/review/%a - %l.txt",
			CoverSize => 100,
);

my $albuminfowidget =
{	class		=> __PACKAGE__,
	tabicon		=> 'plugin-albuminfo',
	tabtitle	=> _"Albuminfo",
	schange		=> \&song_changed,
	group		=> 'Play',
	autoadd_type	=> 'context page text',
};


sub Start {
	Layout::RegisterWidget(PluginAlbuminfo => $albuminfowidget);
}

sub Stop {
	Layout::RegisterWidget(PluginAlbuminfo => undef);
}

sub prefbox {
	my $spin_picsize = ::NewPrefSpinButton(OPT.'CoverSize',50,500, step=>5, page=>10, text1=>_"Cover Size : ", text2=>_"(applied after restart)");
	my $btn_amg      = ::NewIconButton('plugin-artistinfo-allmusic',undef, sub {::main::openurl("http://www.allmusic.com/"); },
					   'none',_"Open allmusic.com website in your browser");
	my $hbox_picsize = ::Hpack($spin_picsize, '-', $btn_amg);

	my $frame_review = Gtk2::Frame->new(_"Review");
	my $entry_path   = ::NewPrefEntry(OPT.'PathFile' => _"Save album info in:", width=>40);
	my $lbl_preview  = Label::Preview->new(event=>'CurSong Option', noescape=>1, wrap=>1, preview=>sub
	{	return '' unless defined $::SongID;
		my $t = ::pathfilefromformat( $::SongID, $::Options{OPT.'PathFile'}, undef,1);
		$t = ::filename_to_utf8displayname($t) if $t;
		$t = $t ? ::PangoEsc(_("example : ").$t) : "<i>".::PangoEsc(_"invalid pattern")."</i>";
		return '<small>'.$t.'</small>';
	});
	my $chk_autosave = ::NewPrefCheckButton(OPT.'AutoSave' => _"Auto-save positive finds"); #, tip=>_"Only works when the review tab is displayed");
	$frame_review->add(::Vpack($entry_path,$lbl_preview,$chk_autosave));

	my $frame_fields = Gtk2::Frame->new(_"Fields");
	my @chk_fields;
	foreach my $field (qw(genre mood style theme)) {
		push(@chk_fields, ::NewPrefCheckButton(OPT.$field=>_(ucfirst($field)."s"), tip=>_"Note: inactive fields must be enabled by the user in the 'Fields' tab in Settings"));
		$chk_fields[-1]->set_sensitive(0) unless Songs::FieldEnabled($field);
	}
	my ($radio_add,$radio_rpl) = ::NewPrefRadio(OPT.'ReplaceFields',undef,_"Add to existing values",1,_"Replace existing values",0);
	my $chk_saveflds = ::NewPrefCheckButton(OPT.'SaveFields'=>_"Auto-save fields with data from allmusic", 
						tip=>_"Save selected fields for all tracks on the same album whenever album data is loaded from AMG or from file.", 
						widget=>::Vpack(\@chk_fields, $radio_add, $radio_rpl));
	$frame_fields->add(::Vpack($chk_saveflds));

	return ::Vpack($hbox_picsize, $frame_review, $frame_fields);
}


#####################################################################
#
# Section: albuminfowidget (the Context pane tab).
#
#####################################################################
sub new {
	my ($class,$options) = @_;
	my $self = bless(Gtk2::VBox->new(0,0), $class);
	$self->{$_} = $options->{$_} for qw/group/;
	my $fontsize = $self->style->font_desc;
	$self->{fontsize} = $fontsize->get_size() / Gtk2::Pango->scale;

	# Heading: cover and album info.
	my $cover = Layout::NewWidget("Cover", {group=>$options->{group}, forceratio=>1, maxsize=>$::Options{OPT.'CoverSize'}, 
						xalign=>0, tip=>_"Click to show fullsize image", click1=>\&cover_popup,
						click3=>sub {::PopupAAContextMenu({self=>$_[0], field=>'album', ID=>$::SongID, gid=>Songs::Get_gid($::SongID,'album'), mode=>'P'});} });
	my $statbox = Gtk2::VBox->new(0,0);
	for my $name (qw/Ltitle Lstats/) {
		my $l = Gtk2::Label->new('');
		$self->{$name} = $l;
		$l->set_justify('center');
		if ($name eq 'Ltitle') { $l->set_line_wrap(1); $l->set_ellipsize('end'); }
		$statbox->pack_start($l,0,0,2);
	}
	$self->{ratingpic} = Gtk2::Image->new();
	$statbox->pack_start($self->{ratingpic},0,0,2);

	# "Refresh", "save" and "search" buttons
	my $refreshbutton = ::NewIconButton('gtk-refresh', undef, sub { song_changed($self,undef,undef,1); }, "none", _"Refresh");
	my $savebutton	  = ::NewIconButton('gtk-save', undef, sub {save_review(::GetSelID($self),$self->{fields})}, "none", _"Save review");
	my $searchbutton = Gtk2::ToggleButton->new();
	$searchbutton->set_relief('none');
	$searchbutton->add(Gtk2::Image->new_from_stock('gtk-find','menu'));
	$searchbutton->signal_connect(toggled => sub {if ($_[0]->get_active()) {$self->manual_search()} else {$self->song_changed()}});
	my $buttonbox = Gtk2::HBox->new();
	$buttonbox->pack_end($searchbutton,0,0,0);
	$buttonbox->pack_end($savebutton,0,0,0); # unless $::Options{OPT.'AutoSave'};
	$buttonbox->pack_end($refreshbutton,0,0,0);
	$statbox->pack_end($buttonbox,0,0,0);
	my $stateventbox = Gtk2::EventBox->new(); # To catch mouse events
	$stateventbox->add($statbox);
	$stateventbox->signal_connect(button_press_event => sub {my ($stateventbox, $event) = @_; return 0 unless $event->button == 3; my $ID = ::GetSelID($self);
								 ::PopupAAContextMenu({ self=>$stateventbox, mode=>'P', field=>'album', ID=>$ID, gid=>Songs::Get_gid($ID,'album') }) if defined $ID; return 1; } );
	my $coverstatbox = Gtk2::HBox->new(0,0);
	$coverstatbox->pack_start($cover,0,0,0);
	$coverstatbox->pack_end($stateventbox,1,1,5);

	# For the review: a TextView in a ScrolledWindow in a HBox
	my $textview = Gtk2::TextView->new();
	$self->signal_connect(map => \&song_changed);
	$textview->set_cursor_visible(0);
	$textview->set_wrap_mode('word');
	$textview->set_pixels_above_lines(2);
	$textview->set_editable(0);
	$textview->set_left_margin(5);
	$textview->set_has_tooltip(1);
	$textview->signal_connect(button_release_event	  => \&button_release_cb);
	$textview->signal_connect(motion_notify_event	  => \&update_cursor_cb);
	$textview->signal_connect(visibility_notify_event => \&update_cursor_cb);
	$textview->signal_connect(query_tooltip		  => \&update_cursor_cb);
	my $sw = Gtk2::ScrolledWindow->new();
	$sw->add($textview);
	$sw->set_shadow_type('none');
	$sw->set_policy('automatic','automatic');
	my $infoview = Gtk2::HBox->new();
	$infoview->set_spacing(0);
	$infoview->pack_start($sw,1,1,0);
	$textview->show();

	# Manual search layout
	my $searchview = Gtk2::VBox->new();
	$self->{search} = my $search  = Gtk2::Entry->new();
	$search->set_tooltip_text(_"Enter album name");
	my $Bsearch = ::NewIconButton('gtk-find', _"Search");
	my $Bok     = Gtk2::Button->new_from_stock('gtk-ok');
	my $Bcancel = Gtk2::Button->new_from_stock('gtk-cancel');
	$Bok    ->set_size_request(80, -1);
	$Bcancel->set_size_request(80, -1);
	$self->{resultsbox}	= my $resultsbox = Gtk2::VBox->new(0,0);
	my $scrwin  = Gtk2::ScrolledWindow->new();
	$scrwin->set_policy('automatic', 'automatic');
	$scrwin->add_with_viewport($resultsbox);
	$searchview->add( ::Vpack(['_', $search, $Bsearch],
				  '_',  $scrwin,
				  '-',  ['-', $Bcancel, $Bok]) );
	$search ->signal_connect(activate => \&new_search ); # Pressing Enter in the search entry.
	$Bsearch->signal_connect(clicked  => \&new_search );
	$Bok    ->signal_connect(clicked  => \&entry_selected_cb );
	$Bcancel->signal_connect(clicked  => \&song_changed );
	$scrwin ->signal_connect(key_press_event => sub {$self->entry_selected_cb() if $_[1]->keyval == $Gtk2::Gdk::Keysyms{Return};});
	$scrwin ->signal_connect(key_press_event => sub {$self->song_changed()      if $_[1]->keyval == $Gtk2::Gdk::Keysyms{Escape};});
	$search ->signal_connect(key_press_event => sub {$self->song_changed()      if $_[1]->keyval == $Gtk2::Gdk::Keysyms{Escape};});

	# Pack it all into self (a VBox)
	$self->pack_start($coverstatbox,0,0,0);
	$self->pack_start($infoview,1,1,0);
	$self->pack_start($searchview,1,1,0);
	$infoview->show();
	$searchview->hide();
	$searchview->signal_connect(  map => sub {$searchbutton->set_active(1)});
	$searchview->signal_connect(unmap => sub {$searchbutton->set_active(0)});
	$self->signal_connect(destroy => sub {$_[0]->cancel()}); # FIXME: Causes warning at quit if plugin was deactivated during session.

	$self->{buffer} = $textview->get_buffer();
	$self->{infoview} = $infoview;
	$self->{searchview} = $searchview;
	return $self;
}

sub update_cursor_cb {
	my $textview = $_[0];
	my (undef,$wx,$wy,undef) = $textview->window->get_pointer();
	my ($x,$y) = $textview->window_to_buffer_coords('widget',$wx,$wy);
	my $iter = $textview->get_iter_at_location($x,$y);
	my $cursor = 'xterm';
	for my $tag ($iter->get_tags()) {
		$cursor = 'hand2' if $tag->{tip};
		$textview->set_tooltip_text($tag->{tip} || '');
	}
	return if ($textview->{cursor} || '') eq $cursor;
	$textview->{cursor} = $cursor;
	$textview->get_window('text')->set_cursor(Gtk2::Gdk::Cursor->new($cursor));
}

# Mouse button pressed in textview. If link: open url in browser.
sub button_release_cb {
	my ($textview,$event) = @_;
	my $self = ::find_ancestor($textview,__PACKAGE__);
	return ::FALSE unless $event->button == 1;
	my ($x,$y) = $textview->window_to_buffer_coords('widget',$event->x, $event->y);
	my $iter = $textview->get_iter_at_location($x,$y);
	for my $tag ($iter->get_tags) {
		if ($tag->{url}) {
			::main::openurl($tag->{url});
			last;
		} elsif ($tag->{field}) {
			Songs::Set(Songs::MakeFilterFromGID('album', Songs::Get_gid(::GetSelID($self),'album'))->filter(), '+'.$tag->{field} => $tag->{val});
		}
	}
	return ::FALSE;
}

sub cover_popup {
	my ($self, $event) = @_;
	my $menu = Gtk2::Menu->new();
	$menu->modify_bg('GTK_STATE_NORMAL',Gtk2::Gdk::Color->parse('black')); # black bg for the cover-popup
	my $ID = ::GetSelID($self);
	my $aID = Songs::Get_gid($ID,'album');
	if (my $img = Gtk2::Image->new_from_file(AAPicture::GetPicture('album',$aID))) {
		my $apic = Gtk2::MenuItem->new();
		$apic->modify_bg('GTK_STATE_SELECTED',Gtk2::Gdk::Color->parse('black'));
		$apic->add($img);
		$apic->show_all();
		$menu->append($apic);
		$menu->popup (undef, undef, undef, undef, $event->button, $event->time);
		return 1;
	} else {
		return 0;
	}
}

# Print warnings in the text buffer
sub print_warning {
	my ($self,$text) = @_;
	my $buffer = $self->{buffer};
	$buffer->set_text("");
	my $iter = $buffer->get_start_iter();
	my $fontsize = $self->{fontsize};
	my $tag_noresults = $buffer->create_tag(undef,justification=>'center',font=>$fontsize*2,foreground_gdk=>$self->style->text_aa("normal"));
	$buffer->insert_with_tags($iter,"\n$text",$tag_noresults);
	$buffer->set_modified(0);
}

# Print review (and additional data) in the text buffer
sub print_review {
	my ($self) = @_;
	my $buffer = $self->{buffer};
	$buffer->set_text("");
	my $fontsize = $self->{fontsize};
	my $tag_h2 = $buffer->create_tag(undef, font=>$fontsize+1, weight=>Gtk2::Pango::PANGO_WEIGHT_BOLD);
	my $tag_b  = $buffer->create_tag(undef, weight=>Gtk2::Pango::PANGO_WEIGHT_BOLD);
	my $tag_i  = $buffer->create_tag(undef, style=>'italic');
	my $iter = $buffer->get_start_iter();
	if ($self->{fields}{label})    {$buffer->insert_with_tags($iter,_"Label:  ",$tag_b); $buffer->insert($iter,"$self->{fields}{label}\n")}
	if ($self->{fields}{rec_date}) {$buffer->insert_with_tags($iter,_"Recording date:  ",$tag_b); $buffer->insert($iter,"$self->{fields}{rec_date}\n")}
	if ($self->{fields}{rls_date}) {$buffer->insert_with_tags($iter,_"Release date:  ",$tag_b); $buffer->insert($iter,"$self->{fields}{rls_date}\n");}
	if ($self->{fields}{rating})   {$buffer->insert_with_tags($iter,_"AMG Rating: ",$tag_b);
					$buffer->insert_pixbuf($iter, Songs::Stars($self->{fields}{rating}, 'rating')); $buffer->insert($iter,"\n");}
	if ($self->{fields}{style} || $self->{fields}{genre})    {
		$buffer->insert_with_tags($iter, _"Genres:  ",$tag_b);
		my $i = 0;
		foreach my $g (@{$self->{fields}{style}}, @{$self->{fields}{genre}}) {
			my $tag  = $buffer->create_tag(undef, foreground=>"#4ba3d2", underline=>'single');
			$tag->{field} = 'genre'; $tag->{val} = $g; $tag->{tip} = _"Add $g to genres for all tracks on this album.";
			$buffer->insert_with_tags($iter,"$g",$tag); $buffer->insert($iter,", ") if ++$i < scalar(@{$self->{fields}{style}}) + scalar(@{$self->{fields}{genre}});
		}
		$buffer->insert($iter, "\n");
	}
	if ($self->{fields}->{review}) {
		$buffer->insert_with_tags($iter, _"\nReview\n", $tag_h2);
		$buffer->insert_with_tags($iter, _"by ".$self->{fields}->{author}."\n", $tag_i);
		$buffer->insert($iter,$self->{fields}->{review});
	} else {
		$buffer->insert_with_tags($iter,_"\nNo review written.\n",$tag_h2);
	}
	my $tag_a  = $buffer->create_tag(undef, foreground=>"#4ba3d2", underline=>'single');
	$tag_a->{url} = $self->{fields}->{url}; $tag_a->{tip} = $self->{fields}->{url};
	$buffer->insert_with_tags($iter,_"\n\nLookup at allmusic.com",$tag_a);
	$buffer->set_modified(0);
}



#####################################################################
#
# Section: "Manual search" window.
#
#####################################################################
sub manual_search {
	my $self = shift;
	$self->{infoview}->hide();
	$self->{searchview}->show();
	my $gid = Songs::Get_gid(::GetSelID($self), 'album');
	my $album = Songs::Gid_to_Get("album",$gid);
	$self->{search}->set_text(Songs::Gid_to_Get('album', $gid));
	$self->new_search();
}

sub new_search {
	my $self = ::find_ancestor($_[0], __PACKAGE__); # $_[0] can be a button or gtk-entry. Ancestor is an albuminfo object.
	my $album = $self->{search}->get_text();
	$album =~ s|^\s+||; $album =~ s|\s+$||; # remove leading and trailing spaces
	return if $album eq '';
	$self->{resultsbox}->remove($_) for $self->{resultsbox}->get_children();
	$self->{resultsbox}->pack_start(Gtk2::Label->new('Loading...'),0,0,20);
	$self->{resultsbox}->show_all();
	my $url = "http://allmusic.com/search/album/".::url_escapeall($album);
	$self->cancel();
	warn "Albuminfo: fetching AMG search from url $url.\n" if $::debug;
	$self->{waiting} = Simple_http::get_with_cb(cb=>sub {$self->print_results(@_)},url=>$url, cache=>1);
}

sub print_results {
	my ($self,$html,$type,$url) = @_;
	delete $self->{waiting};
	$self->{resultsbox}->remove($_) for $self->{resultsbox}->get_children();
	my $result = parse_amg_search_results($html, $type); # result is a ref to an array of hash refs
	my @radios;
	if ( $#{$result} + 1 ) {
		push(@radios, Gtk2::RadioButton->new(undef, "$_->{artist} - $_->{album} ($_->{year}) on $_->{label}")) foreach @$result;
		my $group = $radios[0]->get_group();
		$radios[$_]->set_group($group) for (1 .. $#radios);
		$self->{resultsbox}->pack_start($_,0,0,0) foreach @radios;
	} else {
		$self->{resultsbox}->pack_start(Gtk2::Label->new(_"No results found."),0,0,20);
	}
	$self->{result} = $result;
	$self->{radios} = \@radios;
	$self->{resultsbox}->show_all();
}

sub entry_selected_cb {
	my $self = ::find_ancestor($_[0], __PACKAGE__); # $_[0] is the 'OK' button. Ancestor is an albuminfo object.
	$self->{searchview}->hide();
	$self->{infoview}->show();
	return unless ( $#{$self->{result}} + 1 );
	my $selected;
	foreach (0 .. $#{$self->{radios}}) {
		if (${$self->{radios}}[$_]->get_active()) {$selected = ${$self->{result}}[$_]; last;}
	}
	warn "Albuminfo: fetching review from url $selected->{url}\n" if $::debug;
	$self->{url} = $selected->{url}.'/review';
	$self->cancel();
	$self->{waiting} = Simple_http::get_with_cb(cb=>sub {$self->load_review(::GetSelID($self),1,@_)}, url=>$self->{url}, cache=>1);
}




#####################################################################
#
# Section: loading and parsing review. Saving review and fields.
#
#####################################################################
sub song_changed {
	my ($widget,$tmp,$group,$force) = @_; # $tmp = ::GetSelID($self), but not always. So we don't use it. $group is also not used.
	my $self = ::find_ancestor($widget, __PACKAGE__);
	return unless $self->mapped() || $::Options{OPT.'SaveFields'};
	$self->{infoview}->show();
	$self->{searchview}->hide();
	my $ID = ::GetSelID($self);
	my $aID = Songs::Get_gid($ID,'album');
	return unless $aID;
	if (!$self->{aID} || $aID != $self->{aID} || $force) { # Check if album has changed or a forced update is required.
		$self->{aID} = $aID;
		$self->album_changed($ID, $aID, $force);
	}
}

sub album_changed {
	my ($self,$ID,$aID,$force) = @_;
	$self->update_titlebox($aID);
	$self->cancel();
	my $album = ::url_escapeall(Songs::Gid_to_Get("album",$aID));
	if ($album eq '') {$self->print_warning(_"Unknown album"); return}
	my $url = "http://allmusic.com/search/album/$album";
	$self->print_warning(_"Loading...");
	unless ($force) { # Try loading from file.
		my $file = ::pathfilefromformat( ::GetSelID($self), $::Options{OPT.'PathFile'}, undef, 1 );
		if ($file && -r $file) {
			::IdleDo('8_albuminfo'.$self,1000,\&load_file,$self,$ID,$file);
			return;
		}
	}
	warn "Albuminfo: fetching search results from url $url\n" if $::debug;
	$self->{waiting} = Simple_http::get_with_cb(cb=>sub {$self->load_search_results($ID,@_)}, url=>$url, cache=>1);
}

sub update_titlebox {
	my ($self,$aID) = @_;
	my $rating = AA::Get("rating:average",'album',$aID);
	$self->{rating} = int($rating+0.5);
	$self->{ratingrange} = AA::Get("rating:range", 'album',$aID);
	$self->{playcount}   = AA::Get("playcount:sum",'album',$aID);
	my $tip = join("\n",	_"Average rating:"	.' '.$self->{rating},
				_"Rating range:"	.' '.$self->{ratingrange},
				_"Total playcount:"	.' '.$self->{playcount});
	$self->{ratingpic}->set_from_pixbuf(Songs::Stars($self->{rating},'rating'));
	$self->{Ltitle}->set_markup( AA::ReplaceFields($aID,"<big><b>%a</b></big>","album",1) );
	$self->{Lstats}->set_markup( AA::ReplaceFields($aID,'<small>by %b\n%y\n%s, %l</small>',"album",1) );
	for my $name (qw/Ltitle Lstats/) { $self->{$name}->set_tooltip_text($tip); }
}

sub load_search_results {
	my ($self,$ID,$html,$type) = @_;
	delete $self->{waiting};
	my $result = parse_amg_search_results($html, $type);
	my ($artist,$year) = ::Songs::Get($ID, qw/artist year/);
	my $url;
	foreach my $entry (@$result) {
		# Pick the first entry with the right artist and year, or if not: just the right artist.
		# if (::superlc($entry->{artist}) eq ::superlc($artist)) {
		if ($entry->{artist} =~ m|$artist|i || $artist =~ m|$entry->{artist}|i) {
			if (!$url || $entry->{year} == $year) {
				warn "Albuminfo: AMG hit: $entry->{album} by $entry->{artist} from year=$entry->{year} ($entry->{url})\n" if $::debug;
				$url = $entry->{url}."/review";
			}
			last if $year && $entry->{year} && $entry->{year} == $year;
		}
	}
	if ($url) {
		$self->{url} = $url;
		warn "Albuminfo: fetching review from url $url\n" if $::debug;
		$self->{waiting} = Simple_http::get_with_cb(cb=>sub {$self->load_review($ID,@_)}, url=>$url, cache=>1);
	} else {
		$self->print_warning(_"No review found");
	}	
}

sub load_review {
	my ($self,$ID,$html,$type) = @_;
	delete $self->{waiting};
	$self->{fields} = parse_amg_album_page($html,$type);
	$self->{fields}{url} = $self->{url}; # So that url gets stored if AutoSave is chosen.
	$self->print_review();
	save_review($ID, $self->{fields}) if $::Options{OPT.'AutoSave'};
	save_fields($ID, $self->{fields}) if $::Options{OPT.'SaveFields'};
}

sub parse_amg_search_results {
	my ($html,$type) = @_;
	$html = decode($html, $type);
	$html =~ s/\n/ /g;
	# Parsing the html yields @res = (url1, album1, artist1, label1, year1, url2, album2, ...)
	my @res = $html =~ m|<a href="(http://allmusic\.com/album.*?)">(.*?)</a></td>\s.*?<td>(.*?)</td>\s.*?<td>(.*?)</td>\s.*?<td>(.*?)</td>|g;
	my @fields = qw/url album artist label year/;
	my @result;
	push(@result, {%_}) while (@_{@fields} = splice(@res, 0, 5)); # create an array of hash refs
	return \@result;
}

sub parse_amg_album_page {
	my ($html,$type) = @_;
	$html = decode($html, $type);
	$html =~ s|\n| |g;
	my $result = {};
	$result->{author} = $1 if $html =~ m|<p class="author">by (.*?)</p>|;
	$result->{review} = $1 if $html =~ m|<p class="text">(.*?)</p>|;
	if ($result->{review}) {
		$result->{review} =~ s|<br\s.*?/>|\n|gi;      # Replace newline tags by newlines.
		$result->{review} =~ s|<p\s.*?/>|\n\n|gi;     # Replace paragraph tags by newlines.
		$result->{review} =~ s|\n{3,}|\n\n|gi;	      # Never more than one empty line.
		$result->{review} =~ s|<.*?>(.*?)</.*?>|$1|g; # Remove the rest of the html tags.
	}
	$result->{rls_date}	= $1 if $html =~ m|<h3>Release Date</h3>\s*?<p>(.*?)</p>|;
	$result->{rec_date}	= $1 if $html =~ m|<h3>Recording Date</h3>\s*?<p>(.*?)</p>|;
	$result->{label}	= $1 if $html =~ m|<h3>Label</h3>\s*?<p>(.*?)</p>|;
	$result->{type}		= $1 if $html =~ m|<h3>Type</h3>\s*?<p>(.*?)</p>|;
	$result->{time}		= $1 if $html =~ m|<h3>Time</h3>\s*?<p>(.*?)</p>|;
	$result->{amgid}	= $1 if $html =~ m|<p class="amgid">(.*?)</p>|; $result->{amgid} =~ s/R\s*/r/;
	$result->{rating}	= 10*($1+1) if $html =~ m|star_rating\((\d+?)\)|;
	my ($genrehtml)		= $html =~ m|<h3>Genre</h3>\s*?<ul.*?>(.*?)</ul>|;
	(@{$result->{genre}})	= $genrehtml =~ m|<li><a.*?>\s.*?(.*?)</a></li>|g if $genrehtml;
	my ($stylehtml)		= $html =~ m|<h3>Style</h3>\s*?<ul.*?>(.*?)</ul>|;
	(@{$result->{style}})	= $stylehtml =~ m|<li><a.*?>(.*?)</a></li>|g if $stylehtml;
	my ($moodshtml)		= $html =~ m|<h3>Moods</h3>\s*?<ul.*?>(.*?)</ul>|;
	(@{$result->{mood}})	= $moodshtml =~ m|<li><a.*?>(.*?)</a></li>|g if $moodshtml;
	my ($themeshtml)	= $html =~ m|<h3>Themes</h3>\s*?<ul.*?>(.*?)</ul>|;
	(@{$result->{theme}})	= $themeshtml =~ m|<li><a.*?>(.*?)</a></li>|g if $themeshtml;
	return $result;
}

# Get right encoding of html and decode it
sub decode {
	my ($html,$type) = @_;
	my $encoding;
	$encoding = lc($1)	 if ($type && $type =~ m|^text/.*; ?charset=([\w-]+)|);
	$encoding = 'utf-8'	 if ($html =~ m|xml version|);
	$encoding = lc($1)	 if ($html =~ m|<meta.*?charset=[ "]*?([\w-]+)[ "]|);
	$encoding = 'cp1252' if ($encoding && $encoding eq 'iso-8859-1'); #microsoft use the superset cp1252 of iso-8859-1 but says it's iso-8859-1
	$encoding ||= 'cp1252'; #default encoding
	$html = Encode::decode($encoding,$html) if $encoding;
	$html = ::decode_html($html) if ($encoding eq 'utf-8');
	return $html;
}	

# Load review from file
sub load_file {
	my ($self,$ID,$file) = @_;
	warn "Albuminfo: loading review from file $file\n" if $::debug;
	$self->{fields} = {};
	if ( open(my$fh, '<', $file) ) {
		local $/ = undef; #slurp mode
		my $text = <$fh>;
		if (my $utf8 = Encode::decode_utf8($text)) {$text = $utf8}
		my (@tmp) = $text =~ m|<(.*?)>(.*)</\1>|gs;
		while (my ($key,$val) = splice(@tmp, 0, 2)) {
			if ($key && $val) {
				if ($key =~ m/genre|mood|style|theme/) {
					@{$self->{fields}{$key}} = split(', ', $val);
				} else {
					$self->{fields}{$key} = $val;
				}
			}
		}
		close $fh;
	}
	$self->print_review();
	save_fields($ID, $self->{fields}) if $::Options{OPT.'SaveFields'}; # We may not have saved when first downloaded.
}


# Save review to file. The format of the file is: <field>values</field>
sub save_review {
	my ($ID,$fields) = @_;
	my $text = "";
	for my $key (sort {lc $a cmp lc $b} keys %{$fields}) { # Sort fields alphabetically
		if ($key =~ m/genre|mood|style|theme/) {
			$text = $text . "<$key>".join(", ", @{$fields->{$key}})."</$key>\n";
		} else {
			$text = $text . "<$key>".$fields->{$key}."</$key>\n";
		}
	}
	my $format = $::Options{OPT.'PathFile'};
	my ($path,$file) = ::pathfilefromformat( $ID, $format, undef, 1 );
	unless ($path && $file) {::ErrorMessage(_"Error: invalid filename pattern"." : $format",$::MainWindow); return}
	return unless ::CreateDir($path,$::MainWindow) eq 'ok';
	if ( open(my$fh, '>:utf8', $path.$file) ) {
		print $fh $text;
		close $fh;
		warn "Albuminfo: Saved review in ".$path.$file."\n" if $::debug;
	} else {
		::ErrorMessage(::__x(_"Error saving review in '{file}' :\n{error}", file => $file, error => $!), $::MainWindow);
	}
}

# Save selected fields (moods, styles etc.) for all tracks in album
sub save_fields {
	my ($ID,$fields) = @_;
	my $IDs = Songs::MakeFilterFromGID('album', Songs::Get_gid($ID,'album'))->filter(); # Songs on this album
	my @updated_fields;
	for my $key (keys %{$fields}) {
		if ($key =~ m/mood|style|theme/ && $::Options{OPT.$key} && $fields->{$key}) {
			if ( $::Options{OPT.'ReplaceFields'} ) {
				push(@updated_fields, $key, $fields->{$key});
			} else {
				push(@updated_fields, '+'.$key, $fields->{$key});
			}
		}		
	}
	Songs::Set($IDs, \@updated_fields) if @updated_fields;
}

# Cancel pending tasks, and abort possible http_wget in progress.
sub cancel {
	my $self = shift;
	delete $::ToDo{'8_albuminfo'.$self};
	$self->{waiting}->abort() if $self->{waiting};
}

1

