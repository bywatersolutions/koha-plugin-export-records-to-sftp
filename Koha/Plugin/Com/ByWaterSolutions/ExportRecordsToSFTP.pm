package Koha::Plugin::Com::ByWaterSolutions::ExportRecordsToSFTP;

use Modern::Perl;

use base qw(Koha::Plugins::Base);

use Cwd  qw( abs_path );
use JSON qw( encode_json decode_json );
use MIME::Base64;

use DateTime;
use File::Temp;
use File::Spec;
use POSIX qw( strftime );
use Net::FTP;
use Net::SFTP::Foreign;
use Koha::DateUtils qw( dt_from_string output_pref );

our $metadata = {
    name            => 'Export Records to SFTP',
    author          => 'Kyle M Hall',
    description     => 'Export MARC records and upload via FTP/SFTP',
    date_authored   => '2025-01-09',
    date_updated    => '2025-01-09',
    minimum_version => '24.05.00.000',
    maximum_version => undef,
    version         => '1.0.0',
};

sub new {
    my ( $class, $args ) = @_;

    $args->{'metadata'} = $metadata;
    $args->{'metadata'}->{'class'} = $class;

    my $self = $class->SUPER::new($args);

    return $self;
}

sub configure {
    my ( $self, $args ) = @_;
    my $cgi = $self->{cgi};

    unless ( $cgi->param('save') ) {
        my $template = $self->get_template( { file => 'configure.tt' } );

        my $jobs_json = $self->retrieve_data('jobs');
        my $jobs      = $jobs_json ? decode_json($jobs_json) : [];

        $template->param( jobs => $jobs );

        print $cgi->header(
            -type     => 'text/html',
            -charset  => 'utf-8',
            -encoding => 'utf-8'
        );
        print $template->output;
    }
    else {
        my @job_ids = $cgi->multi_param('job_id');
        my @jobs;

        foreach my $id (@job_ids) {
            my $job = {
                id          => $id,
                name        => $cgi->param("name_$id"),
                enabled     => $cgi->param("enabled_$id"),
                filename    => $cgi->param("filename_$id"),
                record_type => $cgi->param("record_type_$id"),
                format      => $cgi->param("format_$id"),

                # Export params
                days_back         => $cgi->param("days_back_$id") // 0,
                dont_export_items => $cgi->param("dont_export_items_$id"),
                itemtype          => $cgi->param("itemtype_$id"),
                report_id         => $cgi->param("report_id_$id"),

                # Connection params
                protocol    => $cgi->param("protocol_$id"),
                host        => $cgi->param("host_$id"),
                port        => $cgi->param("port_$id"),
                username    => $cgi->param("username_$id"),
                password    => $cgi->param("password_$id"),
                remote_path => $cgi->param("remote_path_$id"),
            };
            push @jobs, $job;
        }

        $self->store_data(
            {
                jobs               => encode_json( \@jobs ),
                last_configured_by => $self->{cgi}->remote_user,
            }
        );

        $self->go_home();
    }
}

sub install {
    my ( $self, $args ) = @_;
    return 1;
}

sub upgrade {
    my ( $self, $args ) = @_;
    my $dt = dt_from_string();
    $self->store_data( { last_upgraded => $dt->ymd . ' ' . $dt->hms } );
    return 1;
}

sub uninstall {
    my ( $self, $args ) = @_;
    return 1;
}

sub cronjob_nightly {
    my ($self) = @_;

    my $jobs_json = $self->retrieve_data('jobs');
    return unless $jobs_json;

    my $jobs = decode_json($jobs_json);

    foreach my $job (@$jobs) {
        next unless $job->{enabled};
        eval { $self->run_export_job($job); };
        if ($@) {
            warn "Error running export job '" . $job->{name} . "': $@";
        }
    }
}

sub run_export_job {
    my ( $self, $job ) = @_;

    my $tempdir = File::Temp->newdir();
    my $dirname = $tempdir->dirname;

    # Calculate Filename
    my $filename = $job->{filename} || 'export_%Y-%m-%d';
    $filename .= '.mrc'
      unless $filename =~ /\./;    # Default extension if missing?

    my $now = DateTime->now( time_zone => 'local' );
    $filename =~ s/%Y/$now->year/eg;
    $filename =~ s/%m/sprintf("%02d", $now->month)/eg;
    $filename =~ s/%d/sprintf("%02d", $now->day)/eg;

    my $output_path = File::Spec->catfile( $dirname, $filename );

    my $script_path = '/usr/share/koha/bin/export_records.pl';

    my @cmd = ($script_path);
    push @cmd, '--record-type', $job->{record_type};
    push @cmd, '--format',      $job->{format};

    # Date handling
    my $days_back = $job->{days_back};
    if ( defined $days_back && $days_back ne '' && $days_back > 0 ) {
        my $dt_start =
          DateTime->now( time_zone => 'local' )->subtract( days => $days_back );
        my $start_date = $dt_start->ymd;
        push @cmd, "--date", "$start_date";
    }

    if ( $job->{dont_export_items} ) {
        push @cmd, '--dont_export_items';
    }

    if ( $job->{itemtype} ) {
        push @cmd, '--itemtype', $job->{itemtype};
    }

    if ( $job->{report_id} ) {
        push @cmd, '--report_id', $job->{report_id};
    }

    push( @cmd, "--filename", $output_path );

    # Execute and redirect to file
    my $cmd_str = join( ' ', @cmd );

    warn "COMMAND: $cmd_str";
    my $res = system($cmd_str);

    if ( $res != 0 ) {
        die "Export command failed: $cmd_str";
    }

    # Check if file exists and has size
    unless ( -s $output_path ) {
        warn "Export generated empty file or failed for job: " . $job->{name};
        return;
    }

    # Upload
    if ( $job->{protocol} eq 'ftp' ) {
        $self->_upload_ftp( $output_path, $filename, $job );
    }
    elsif ( $job->{protocol} eq 'sftp' ) {
        $self->_upload_sftp( $output_path, $filename, $job );
    }
}

sub _upload_ftp {
    my ( $self, $local_file, $remote_filename, $job ) = @_;

    my $ftp = Net::FTP->new( $job->{host}, Port => $job->{port} || 21,
        Passive => 1 )    # Default passive
      or die "Cannot connect to " . $job->{host} . ": $@";

    $ftp->login( $job->{username}, $job->{password} )
      or die "Cannot login to FTP " . $job->{host} . ": " . $ftp->message;

    if ( $job->{remote_path} ) {
        $ftp->cwd( $job->{remote_path} )
          or die "Cannot change directory to "
          . $job->{remote_path} . ": "
          . $ftp->message;
    }

    $ftp->put( $local_file, $remote_filename )
      or die "Put failed: " . $ftp->message;

    $ftp->quit;
}

sub _upload_sftp {
    my ( $self, $local_file, $remote_filename, $job ) = @_;

    my %args = (
        host     => $job->{host},
        user     => $job->{username},
        password => $job->{password},
        port     => $job->{port} || 22,

        # autodie => 1, # handled via error checking
    );

    my $sftp = Net::SFTP::Foreign->new(%args);

    if ( $sftp->error ) {
        die "SFTP Connection failed: " . $sftp->error;
    }

    my $remote_path = $remote_filename;
    if ( $job->{remote_path} ) {
        $remote_path =
          File::Spec->catfile( $job->{remote_path}, $remote_filename );

    # Helper might handle path separators incorrectly if remote is different OS,
    # but SFTP usually expects forward slashes.
        $remote_path = $job->{remote_path} . '/' . $remote_filename;

        # Clean up double slashes just in case
        $remote_path =~ s{/+}{/}g;
    }

    $sftp->put( $local_file, $remote_path )
      or die "SFTP Put failed: " . $sftp->error;
}

1;
