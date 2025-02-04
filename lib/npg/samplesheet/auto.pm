package npg::samplesheet::auto;

use Moose;
use namespace::autoclean;
use Try::Tiny;
use File::Basename;
use Readonly;
use File::Copy;
use File::Spec::Functions;

use npg::samplesheet;
use npg_tracking::Schema;
use WTSI::DNAP::Warehouse::Schema;
use st::api::lims;
use st::api::lims::samplesheet;

with q(MooseX::Log::Log4perl);

our $VERSION = '0';

Readonly::Scalar my $DEFAULT_SLEEP => 90;

=head1 NAME

npg::samplesheet::auto

=head1 VERSION

=head1 SYNOPSIS

  use npg::samplesheet::auto;
  use Log::Log4perl qw(:easy);
  BEGIN{ Log::Log4perl->easy_init({level=>$INFO,}); }
  npg::samplesheet::auto->new()->loop();

=head1 DESCRIPTION

Class for creating  Illumina MiSeq samplesheets automatically
for runs which are pending.

=head1 SUBROUTINES/METHODS

=head2 npg_tracking_schema

=cut

has 'npg_tracking_schema' => (
  'isa'        => 'npg_tracking::Schema',
  'is'         => 'ro',
  'lazy_build' => 1,
);
sub _build_npg_tracking_schema {
  return npg_tracking::Schema->connect();
}

=head2 mlwh_schema

=cut

has 'mlwh_schema' => (
  'isa'        => 'WTSI::DNAP::Warehouse::Schema',
  'is'         => 'ro',
  'lazy_build' => 1,
);
sub _build_mlwh_schema {
  return WTSI::DNAP::Warehouse::Schema->connect();
}

=head2 sleep_interval

=cut

has 'sleep_interval' => (
  'is'      => 'ro',
  'isa'     => 'Int',
  'default' => $DEFAULT_SLEEP,
);

=head2 loop

Repeat the process step with the intervening sleep interval.

=cut

sub loop {
  my $self = shift;
  while(1) { $self->process(); sleep $self->sleep_interval;}
  return;
};

=head2 process

Find all pending MiSeq runs and create an Illumina  samplesheet for each
of them if one does not already exist.

=cut

sub process {
  my $self = shift;
  my $rt = $self->_pending->run_statuses->search({iscurrent=>1})
                ->related_resultset(q(run));
  my $rs = $rt->search(
    {q(run.id_instrument_format) => $self->_miseq->id_instrument_format});
  $self->log->debug( $rs->count. q[ ] .($self->_miseq->model).
    q[ runs marked as ] .($self->_pending->description));
  while(my$r=$rs->next){
    my $id_run = $r->id_run;
    $self->log->info('Considering ' . join q[,],$id_run,$r->instrument->name);

    my $l = st::api::lims->new(
      position         => 1,
      id_run           => $id_run,
      id_flowcell_lims => $r->batch_id,
      driver_type      => q(ml_warehouse),
      mlwh_schema      => $self->mlwh_schema
    );

    my $ss = npg::samplesheet->new(run => $r, lims => [$l]);

    my$o=$ss->output;
    my $generate_new = 1;

    if(-e $o) {
      my $other_id_run = _id_run_from_samplesheet($o);
      if ($other_id_run && $other_id_run == $id_run) {
        $self->log->info(qq($o already exists for $id_run));
        $generate_new = 0;
      } else {
        $self->log->info(qq(Will move existing $o));
        _move_samplesheet($o);
      }
    }

    if ($generate_new) {
      try {
        $ss->process;
        $self->log->info(qq($o created for run ).($r->id_run));
      } catch {
        $self->log->error(qq(Trying to create $o for run ).($r->id_run).
                          qq( experienced error: $_));
      }
    }
  }
  return;
}

has '_miseq' => (
  'is'         => 'ro',
  'lazy_build' => 1,
);
sub _build__miseq {
  my $self=shift;
  return $self->npg_tracking_schema->resultset(q(InstrumentFormat))
              ->find({q(model)=>q(MiSeq)});
}

has '_pending' => (
  'is'         => 'ro',
  'lazy_build' => 1,
);
sub _build__pending {
  my $self=shift;
  return $self->npg_tracking_schema->resultset(q(RunStatusDict))
              ->find({q(description)=>q(run pending)});
}

sub _id_run_from_samplesheet {
  my $file_path = shift;
  my $id_run;
  try {
    my $sh = st::api::lims::samplesheet->new(path => $file_path);
    $sh->data; # force to parse the file
    if ($sh->id_run) {
      $id_run = int $sh->id_run;
    }
  };
  return $id_run;
}

sub _move_samplesheet {
  my $file_path = shift;

  my($filename, $dirname) = fileparse($file_path);
  $dirname =~ s/\/$//smx; #drop last forward slash if any
  my $dirname_dest = $dirname . '_old';
  my $filename_dest = $filename . '_invalid';
  my $moved;
  if (-d $dirname_dest) {
    $moved = move($file_path, catdir($dirname_dest, $filename_dest));
  }
  if (!$moved) {
    move($file_path, catdir($dirname, $filename_dest));
  }
  return;
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=head1 DIAGNOSTICS

=head1 CONFIGURATION AND ENVIRONMENT

=head1 DEPENDENCIES

=over

=item File::Basename

=item File::Copy

=item Moose

=item namespace::autoclean

=item MooseX::Log::Log4perl

=item Readonly

=item File::Spec::Functions

=item Try::Tiny

=item npg_tracking::Schema

=item npg::samplesheet

=item st:api::lims

=item st::api::lims::samplesheet

=item WTSI::DNAP::Warehouse::Schema

=back

=head1 INCOMPATIBILITIES

=head1 BUGS AND LIMITATIONS

=head1 AUTHOR

David K. Jackson E<lt>david.jackson@sanger.ac.ukE<gt>

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2012,2013,2014,2019,2021,2023 GRL.

This file is part of NPG.

NPG is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.

=cut

