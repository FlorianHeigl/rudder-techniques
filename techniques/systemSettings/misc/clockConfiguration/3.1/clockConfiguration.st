#####################################################################################
# Copyright 2011 Normation SAS
#####################################################################################
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, Version 3.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
#####################################################################################

######################################################
# Configure the ntp
# If ntp is not installed, install it (linux)
# Change the server configuration, and restart the daemon
# if the configuration changed
# Caution : a missing feature in cfe prevents from adding ,0x1 at the end of the domain name
# so it's only safe to use with ips for now

bundle agent check_clock_configuration
{

  vars:
      "ntpServers" slist => {&CLOCK_NTPSERVERS: { "&it&"};separator=", "&};

      "target_timezone" string => ifelse( strcmp("&CLOCK_TIMEZONE&", "custom"), "&CLOCK_TIMEZONE_CUSTOM&", "&CLOCK_TIMEZONE&" );

    !windows::
      "linux_timezone"   string => "${tz_variables.tz_linux[${target_timezone}]}";

    windows::
      # For windows, we must extract both ip and domain name values
      #"ipv4" slist => grep("(?:\\d{1,3}\.){3}\\d{1,3}","ntpServers");

      #domain slist => not one of the above
      # check that list aren't empty using reglist

      &if(CLOCK_FQDNNTP)&
      "keytemp" string => join("\,0x1 ", ntpServers);
      "serverskey" string => "${keytemp}\,0x1";
      &else&
      "serverskey" string => join(" ", ntpServers);
      &endif&

      "current_timezone" string => execresult("\"${sys.winsysdir}\tzutil.exe\" /g", "useshell");
      "windows_timezone" string => "${tz_variables.tz_win[${target_timezone}]}";

  classes:

    !windows::
      "clock_vardef" expression => isvariable("tz_variables.tz_linux[${target_timezone}]");

    windows::
      "clock_vardef" expression => isvariable("tz_variables.tz_win[${target_timezone}]");

    any::
      # We don't edit the TZ if no valid variable is present - probably user input field gone wrong.
      "clock_timezone_nochange" expression => strcmp("&CLOCK_TIMEZONE&","dontchange");
      "clock_timezone_noedit"   expression => "clock_timezone_nochange|!clock_vardef";

      "clock_hwclock_sync" expression => strcmp("&CLOCK_HWSYNC_ENABLE&","true");

      "ntp_config_file_exists" expression => fileexists("/etc/ntp.conf");

    clock_vardef.windows::
      # check if we need to change the windows timezone
      "need_to_change_timezone" not => strcmp("${windows_timezone}", "${current_timezone}");

    any::
      "pass3" expression => "pass2";
      "pass2" expression => "pass1";
      "pass1" expression => "any";

  files:

    # Adjust ntp.conf (Add the servers)
    !windows.(ntp_config_file_exists|ntp_installed)::
      "/etc/ntp.conf"
        edit_line => setNtpServer("@{this.ntpServers}"),
        edit_defaults => noempty_backup,
        classes => kept_if_else("ntpconf_kept", "repaired_ntpconf", "not_repaired_ntpconf");

    # Copy the correct localtime file (distro independant)
    !windows.!clock_timezone_noedit::
      "/etc/localtime"
        copy_from => digest_cp("/usr/share/zoneinfo/${linux_timezone}"),
        comment => "Updating the /etc/localtime file",
        classes => kept_if_else("localtime_kept", "repaired_localtime", "not_repaired_localtime");

    # Edit the distro dependant files to set the TZ on boot
    redhat.!clock_timezone_noedit::
      "/etc/sysconfig/clock"
        edit_line => EditCentOSTimezone("${linux_timezone}"),
        edit_defaults => noempty_backup,
        classes => kept_if_else("redhattz_kept", "repaired_redhattz", "not_repaired_redhattz");

    SuSE.!clock_timezone_noedit::
      "/etc/sysconfig/clock"
        edit_line => EditSuSETimezone("${linux_timezone}"),
        edit_defaults => noempty_backup,
        classes => kept_if_else("susetz_kept", "repaired_susetz", "not_repaired_susetz");

    debian.!clock_timezone_noedit::
      "/etc/timezone"
        edit_defaults => empty_backup,
        edit_line => EditDebianTimezone("${linux_timezone}"),
        classes => kept_if_else("debiantz_kept", "repaired_debiantz", "not_repaired_debiantz");

  # Install the NTP package
  packages:
    linux.!SuSE_10.!SuSE_11::
      "ntp"
        package_policy  => "add",
        package_method  => generic,
        classes => kept_if_else("ntp_install_kept", "ntp_installed", "cant_install_ntp"),
        comment => "Installing ntp";

    SuSE_11::
      "ntp"
        package_policy => "add",
        package_method => zypper,
        classes => kept_if_else("ntp_install_kept", "ntp_installed", "cant_install_ntp"),
        comment => "Installing ntp using zypper";

    SuSE_10::
      "xntp"
        package_policy => "add",
        package_method => rudder_rug,
        classes => kept_if_else("ntp_install_kept", "ntp_installed", "cant_install_ntp"),
        comment => "Installing xntp using rug";

  methods:


    # Global report for the "Time synchronization (NTP)" component - Linux
    pass3.((ntp_install_kept|(!linux.!windows)).ntpconf_kept.!ntpd_down)::
      "any" usebundle => rudder_common_report("ntpConfiguration", "result_success", "&TRACKINGKEY&", "Time synchronization (NTP)", "None", "ntp daemon installed, configured and running");

    pass3.(ntp_installed|repaired_ntpconf|ntp_restarted)::
      "any" usebundle => rudder_common_report("ntpConfiguration", "result_repaired", "&TRACKINGKEY&", "Time synchronization (NTP)", "None", "ntp service (package, configuration and/or process) repaired");

    # Global report for the "Time synchronization (NTP)" component - Windows
    pass3.ntp_regkept::
      "any" usebundle => rudder_common_report("ntpConfiguration", "result_success", "&TRACKINGKEY&", "Time synchronization (NTP)", "None", "NTP service configured and running");

    pass3.(ntp_regset.ntp_win32time_started)::
      "any" usebundle => rudder_common_report("ntpConfiguration", "result_repaired", "&TRACKINGKEY&", "Time synchronization (NTP)", "None", "NTP service repaired, it is now configured and running");

    # Individual reports for the "Time synchronization (NTP)" component's parts
    pass3.cant_install_ntp::
      "any" usebundle => rudder_common_report("ntpConfiguration", "result_error", "&TRACKINGKEY&", "Time synchronization (NTP)", "None", "ntp package could not be installed");

    pass3.ntp_installed::
      "any" usebundle => rudder_common_report("ntpConfiguration", "log_repaired", "&TRACKINGKEY&", "Time synchronization (NTP)", "None", "ntp package installed");

    pass3.ntp_install_kept::
      "any" usebundle => rudder_common_report("ntpConfiguration", "log_info", "&TRACKINGKEY&", "Time synchronization (NTP)", "None", "ntp package already installed");

    pass3.(!linux.!windows)::
      "any" usebundle => rudder_common_report("ntpConfiguration", "log_info", "&TRACKINGKEY&", "Time synchronization (NTP)", "None", "Support to check if ntp is installed not available on this platform");

    pass3.repaired_ntpconf::
      "any" usebundle => rudder_common_report("ntpConfiguration", "log_repaired", "&TRACKINGKEY&", "Time synchronization (NTP)", "None", "ntpd configuration updated");

    pass3.not_repaired_ntpconf::
      "any" usebundle => rudder_common_report("ntpConfiguration", "result_error", "&TRACKINGKEY&", "Time synchronization (NTP)", "None", "ntpd configuration could not be changed");

    pass3.ntpd_down::
      "any" usebundle => rudder_common_report("ntpConfiguration", "log_info", "&TRACKINGKEY&", "Time synchronization (NTP)", "None", "ntpd process was not running");

    pass3.ntp_restarted::
      "any" usebundle => rudder_common_report("ntpConfiguration", "log_repaired", "&TRACKINGKEY&", "Time synchronization (NTP)", "None", "ntpd process restarted");

    pass3.cant_restart_ntp::
      "any" usebundle => rudder_common_report("ntpConfiguration", "result_error", "&TRACKINGKEY&", "Time synchronization (NTP)", "None", "ntpd process could not be restarted");

    pass3.ntp_regset::
      "any" usebundle => rudder_common_report("ntpConfiguration", "log_repaired", "&TRACKINGKEY&", "Time synchronization (NTP)", "None", "NTP service configured in the Windows registry. W32Time will restart");

    pass3.ntp_regfail::
      "any" usebundle => rudder_common_report("ntpConfiguration", "result_error", "&TRACKINGKEY&", "Time synchronization (NTP)", "None", "NTP service could not be configured in the Windows registry");

    pass3.ntp_regkept::
      "any" usebundle => rudder_common_report("ntpConfiguration", "log_info", "&TRACKINGKEY&", "Time synchronization (NTP)", "None", "NTP service was already configured in the Windows registry");

    pass3.ntp_win32time_started::
      "any" usebundle => rudder_common_report("ntpConfiguration", "log_info", "&TRACKINGKEY&", "Time synchronization (NTP)", "None", "NTP service (W32Time) restarted");


    # Global reports for the "Time zone" component's parts
    pass3.(repaired_localtime|repaired_redhattz|repaired_debiantz|repaired_susetz)::
      "any" usebundle => rudder_common_report("ntpConfiguration", "result_repaired", "&TRACKINGKEY&", "Time zone", "None", "Time zone was reset");

    pass3.(localtime_kept.((redhat.redhattz_kept)|(debian.debiantz_kept)|(SuSE.susetz_kept)))::
      "any" usebundle => rudder_common_report("ntpConfiguration", "result_success", "&TRACKINGKEY&", "Time zone", "None", "Time zone was already correctly configured");

    pass3.clock_timezone_nochange::
      "any" usebundle => rudder_common_report("ntpConfiguration", "result_success", "&TRACKINGKEY&", "Time zone", "None", "Time zone edition disabled");

    pass3.!clock_timezone_nochange.!clock_vardef::
      "any" usebundle => rudder_common_report("ntpConfiguration", "result_error", "&TRACKINGKEY&", "Time zone", "None", "Time zone provided is not valid");

    # Individual reports for the "Time zone" component's parts
    pass3.((windows.!clock_timezone_noedit).clock_vardef.!need_to_change_timezone)::
      "any" usebundle => rudder_common_report("ntpConfiguration", "result_success", "&TRACKINGKEY&", "Time zone", "None", "Time zone was already correctly configured");

    pass3.(timezone_change_repaired|repaired_localtime)::
      "any" usebundle => rudder_common_report("ntpConfiguration", "log_repaired", "&TRACKINGKEY&", "Time zone", "None", "Time zone was reset (localtime file changed)");

    pass3.(not_repaired_localtime|timezone_change_failed)::
      "any" usebundle => rudder_common_report("ntpConfiguration", "result_error", "&TRACKINGKEY&", "Time zone", "None", "Time zone could not be set (localtime file could not be changed)");

    pass3.localtime_kept::
      "any" usebundle => rudder_common_report("ntpConfiguration", "log_info", "&TRACKINGKEY&", "Time zone", "None", "Time zone was already set (localtime file didn't need changing)");

    pass3.repaired_redhattz::
      "any" usebundle => rudder_common_report("ntpConfiguration", "log_repaired", "&TRACKINGKEY&", "Time zone", "None", "Red Hat-style specific time zone parameters updated (/etc/sysconfig/clock)");

    pass3.not_repaired_redhattz::
      "any" usebundle => rudder_common_report("ntpConfiguration", "result_error", "&TRACKINGKEY&", "Time zone", "None", "Could not update Red Hat-style time zone parameters (/etc/sysconfig/clock)");

    pass3.redhattz_kept::
      "any" usebundle => rudder_common_report("ntpConfiguration", "log_info", "&TRACKINGKEY&", "Time zone", "None", "Red Hat-style time zone parameters already correct (/etc/sysconfig/clock)");

    pass3.repaired_debiantz::
      "any" usebundle => rudder_common_report("ntpConfiguration", "log_repaired", "&TRACKINGKEY&", "Time zone", "None", "Debian-style time zone parameters updated (/etc/timezone)");

    pass3.not_repaired_debiantz::
      "any" usebundle => rudder_common_report("ntpConfiguration", "result_error", "&TRACKINGKEY&", "Time zone", "None", "Could not update Debian-style time zone parameters (/etc/timezone)");

    pass3.debiantz_kept::
      "any" usebundle => rudder_common_report("ntpConfiguration", "log_info", "&TRACKINGKEY&", "Time zone", "None", "Debian-style time zone parameters already correct (/etc/timezone)");

    pass3.repaired_susetz::
      "any" usebundle => rudder_common_report("ntpConfiguration", "log_repaired", "&TRACKINGKEY&", "Time zone", "None", "SuSE-style time zone parameters updated (/etc/sysconfig/clock)");

    pass3.not_repaired_susetz::
      "any" usebundle => rudder_common_report("ntpConfiguration", "result_error", "&TRACKINGKEY&", "Time zone", "None", "Could not update SuSE-style time zone parameters (/etc/sysconfig/clock)");

    pass3.susetz_kept::
      "any" usebundle => rudder_common_report("ntpConfiguration", "log_info", "&TRACKINGKEY&", "Time zone", "None", "SuSE-style time zone parameters already correct (/etc/sysconfig/clock)");

    # Global reports for the "Hardware clock (RTC)" component
    pass3.(!windows.!ntp_hwclock_sync_error.!ntp_hwclock_synced.clock_hwclock_sync)::
      "any" usebundle => rudder_common_report("ntpConfiguration", "result_success", "&TRACKINGKEY&", "Hardware clock (RTC)", "None", "It is not yet time to synchronize the hardware clock with the NTP time. Skipping...");

    pass3.ntp_hwclock_synced::
      "any" usebundle => rudder_common_report("ntpConfiguration", "result_success", "&TRACKINGKEY&", "Hardware clock (RTC)", "None", "The hardware clock has been synchronized with the NTP time");

    pass3.ntp_hwclock_sync_error::
      "any" usebundle => rudder_common_report("ntpConfiguration", "result_error", "&TRACKINGKEY&", "Hardware clock (RTC)", "None", "The hardware clock could not be synchronized with the NTP time");

    pass3.windows::
      "any" usebundle => rudder_common_report("ntpConfiguration", "result_success", "&TRACKINGKEY&", "Hardware clock (RTC)", "None", "The hardware clock is automatically synchronized with the NTP time on Windows");

    pass3.!clock_hwclock_sync.!windows::
      "any" usebundle => rudder_common_report("ntpConfiguration", "result_success", "&TRACKINGKEY&", "Hardware clock (RTC)", "None", "No synchronization with the hardware clock was requested");

  processes:

    # If NTP is down, define its restart class
      "ntpd"
        restart_class => "ntpd_down";

  commands:

    # Restart commands
    !windows.!redhat.(repaired_ntpconf|repaired_localtime|repaired_debiantz|repaired_susetz|ntpd_down)::
      "/etc/init.d/ntp"
        args => "restart",
        classes => cf2_if_else("ntp_restarted", "cant_restart_ntp"),
        comment => "restarting ntp";

    redhat.(repaired_ntpconf|repaired_localtime|repaired_redhattz|ntpd_down)::
      "/etc/init.d/ntpd"
        args => "restart",
        classes => cf2_if_else("ntp_restarted", "cant_restart_ntp"),
        comment => "restarting ntp";

    (windows.!clock_timezone_noedit).clock_vardef.need_to_change_timezone::
      "\"${sys.winsysdir}\tzutil.exe\""
        args => "/s \"${windows_timezone}\"",
        contain => in_shell,
        classes => rudder_common_classes("timezone_change"),
        comment => "set the windows time zone";

    (windows.!clock_timezone_noedit).ntp_regset::
      "\"${sys.winsysdir}\net.exe\""
        args => "stop W32Time",
        contain => in_shell,
        classes => cf2_if_else("ntp_winsvcstop", "ntp_winsvcstop"),
        comment => "Restart the windows NTP service";

    (windows.!clock_timezone_noedit).ntp_winsvcstop::
      "\"${sys.winsysdir}\net.exe\""
        args => "start W32Time",
        contain => in_shell,
        classes => cf2_if_else("ntp_win32time_started", "ntp_win32time_error"),
        comment => "Restart the windows NTP service";

    # HW clock sync command
    !windows.clock_hwclock_sync::
      "/sbin/hwclock"
        args => "--systohc",
        action => if_elapsed("&CLOCK_SYNCSCHED&"),
        classes => cf2_if_else("ntp_hwclock_synced", "ntp_hwclock_sync_error"),
        comment => "synchronizing hardware clock";

&if(NOVA)&
  databases:

    windows::

      "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\W32Time\Parameters"

        database_operation => "create",
        database_rows => { "Type,REG_SZ,NTP", "NtpServer,REG_SZ,${serverskey}"},
        database_type => "ms_registry",
        comment => "Editing the windows registry to set the required NTP entries",
        classes => kept_if_else("ntp_regkept", "ntp_regset", "ntp_regfail");
&endif&

}


bundle edit_line setNtpServer(serverlist)
{
  delete_lines:
      "server.*";

  insert_lines:
      "${rudder_parameters.rudder_file_edit_header}"
        location => start,
        insert_type => "preserve_block";

      "server ${serverlist}";

}

bundle edit_line EditCentOSTimezone(tz)
{

  insert_lines:
      "${rudder_parameters.rudder_file_edit_header}"
        location => start,
        insert_type => "preserve_block";

  replace_patterns:

# Ensure the ZONE is correct

      "^[# ]*ZONE\=(?!${tz}).*$"

        replace_with => value("ZONE=${tz}");

# Change UTC

      "^[# ]*UTC=\+.*$"
        replace_with => value("UTC=false");

# Change ARC

      "^[# ]*ARC\s+.*$"
        replace_with => value("ARC=false");
}

bundle edit_line EditSuSETimezone(tz)
{

  insert_lines:
      "${rudder_parameters.rudder_file_edit_header}"
        location => start,
        insert_type => "preserve_block";

  replace_patterns:

# Ensure the TIMEZONE is correct

      "^[# ]*TIMEZONE\=(?!\"${tz}\").*$"

        replace_with => value("TIMEZONE=\"${tz}\"");

# Ensure the DEFAULT_TIMEZONE is correct

      "^[# ]*DEFAULT_TIMEZONE\=(?!\"${tz}\").*$"

        replace_with => value("DEFAULT_TIMEZONE=\"${tz}\"");

# Ensure the SYSTOHC is correct

      "^[# ]*SYSTOHC\=(?!\"yes\").*$"

        replace_with => value("SYSTOHC=\"yes\"");

}

bundle edit_line EditDebianTimezone(tz)
{

  insert_lines:

# Ensure the ZONE is correct

      "${tz}";

}
