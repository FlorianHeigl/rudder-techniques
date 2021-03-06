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


bundle agent download_from_shared_folder
{

  vars:

      &COPYFILE_NAME:{name |"copyfile[&i&][name]" string => "&name&";
}&

      &COPYFILE_EXCLUDE_INCLUDE:{exclude_include |"copyfile[&i&][exclude_include]" string => "&exclude_include&";
}&

      &COPYFILE_EXCLUDE_INCLUDE_OPTION:{exclude_include_option |"copyfile[&i&][exclude_include_option]" string => "&exclude_include_option&";
}&

      &COPYFILE_RECURSION:{rec |"copyfile[&i&][recursion]" string => "&rec&";
}&

      &COPYFILE_OWNER:{owner |"copyfile[&i&][owner]" string => "&owner&";
}&

      &COPYFILE_GROUP:{group |"copyfile[&i&][group]" string => "&group&";
}&

      &COPYFILE_PURGE:{purge |"copyfile[&i&][purge]" string => "&purge&";
}&

      &COPYFILE_COMPARE_METHOD:{compare_method |"copyfile[&i&][compare_method]" string => "&compare_method&";
}&

      &COPYFILE_PERM:{perms |"copyfile[&i&][perm]" string => "&perms&";
}&

      &COPYFILE_DESTINATION:{destination |"copyfile[&i&][destination]" string => "&destination&";
}&

      &COPYFILE_POST_HOOK_COMMAND:{command |"copyfile[&i&][posthook]" string => "&command&";
}&

      &TRACKINGKEY:{piuuid |"copyfile[&i&][uuid]" string => "&piuuid&";
}&
      "shared_folder" string => "&SHARED_FILES_FOLDER&";

      "canon_dirname_${index}" string => canonify(dirname("${copyfile[${index}][destination]}"));

      "index" slist => getindices("copyfile");

  iteration_1::
    "extended_modes_${index}"
      string     => "4",
      ifvarclass => "enable_suid_${index}.!enable_sgid_${index}";

    "extended_modes_${index}"
      string     => "2",
      ifvarclass => "!enable_suid_${index}.enable_sgid_${index}";

    "extended_modes_${index}"
      string     => "6",
      ifvarclass => "enable_suid_${index}.enable_sgid_${index}";

    "extended_modes_${index}"
      string     => "0",
      ifvarclass => "!enable_suid_${index}.!enable_sgid_${index}";

  defaults:
      # Add a trailing slash to force considering destination as a directory and avoid replacing it with a file
      "copyfile[${index}][destination]" string => "${copyfile[${index}][destination]}/", if_match_regex => ".*[^\/]",
                                    ifvarclass => "pass1.!is_file_${index}";

  classes:
      "is_valid" not => strcmp("&SHARED_FILES_FOLDER&", "");

      "exist_${index}"                  expression => fileexists("${copyfile[${index}][destination]}");
      "is_file_${index}"                       not => isdir("${copyfile[${index}][destination]}");
      "copy_file_${index}_dest_notdir"         not => isdir(dirname("${copyfile[${index}][destination]}"));
      "copy_file_${index}_user_absent"         not => userexists("${copyfile[${index}][owner]}");
      "copy_file_${index}_group_absent"        not => groupexists("${copyfile[${index}][group]}");
      "need_exclusion_${index}"                and => { isvariable("copyfile[${index}][exclude_include]"), strcmp("${copyfile[${index}][exclude_include_option]}", "exclude") };
      "need_inclusion_${index}"                and => { isvariable("copyfile[${index}][exclude_include]"), strcmp("${copyfile[${index}][exclude_include_option]}", "include") };
      "apply_regex_${index}"                   or  => { "need_exclusion_${index}", "need_inclusion_${index}"};

      &COPYFILE_SUID:{suid |"enable_suid_&i&" expression => strcmp("&suid&", "true");
}&
      &COPYFILE_SGID:{sgid |"enable_sgid_&i&" expression => strcmp("&sgid&", "true");
}&
      # Set a class to define when we need to run the post-modification hook
      &COPYFILE_POST_HOOK_RUN:{run |"execute_command_&i&" expression => strcmp("&run&", "true");
}&
      "iteration_2" expression => "iteration_1";
      "iteration_1" expression => "any";


    any::
      "pass3" expression => "pass2";
      "pass2" expression => "pass1";
      "pass1" expression => "any";

  files:
    is_valid.iteration_2::

      # If it's a directory, without exclusion
      "${copyfile[${index}][destination]}"
        copy_from    => rudder_copy_from("&SHARED_FILES_FOLDER&/${copyfile[${index}][name]}", "${server_info.cfserved}", "${copyfile[${index}][compare_method]}", "false", "false", "${copyfile[${index}][purge]}"),
        depth_search => recurse("${copyfile[${index}][recursion]}"),
        perms        => mog(
                            "${copyfile[${index}][perm]}",
                            "${copyfile[${index}][owner]}",
                            "${copyfile[${index}][group]}"
                           ),
        comment      => "Enforce content of ${copyfile[${index}][destination]} based on the content on the Rudder server with ${copyfile[${index}][compare_method]} method",
        classes      => rudder_common_classes("copy_file_${index}"),
        ifvarclass   => "(!exist_${index}|!is_file_${index}).!apply_regex_${index}";

       # If it's a directory, with exclusion
      "${copyfile[${index}][destination]}"
        copy_from    => rudder_copy_from("&SHARED_FILES_FOLDER&/${copyfile[${index}][name]}", "${server_info.cfserved}", "${copyfile[${index}][compare_method]}", "false", "false", "${copyfile[${index}][purge]}"),
        depth_search => recurse("${copyfile[${index}][recursion]}"),
        file_select  => exclude("${copyfile[${index}][exclude_include]}"),
        perms        => mog(
                            "${copyfile[${index}][perm]}",
                            "${copyfile[${index}][owner]}",
                            "${copyfile[${index}][group]}"
                           ),
        comment      => "Enforce content of ${copyfile[${index}][destination]} based on the content on the Rudder server with ${copyfile[${index}][compare_method]} method",
        classes      => rudder_common_classes("copy_file_${index}"),
        ifvarclass   => "(!exist_${index}|!is_file_${index}).need_exclusion_${index}";

       # If it's a directory, with inclusion
      "${copyfile[${index}][destination]}"
        copy_from    => rudder_copy_from("&SHARED_FILES_FOLDER&/${copyfile[${index}][name]}", "${server_info.cfserved}", "${copyfile[${index}][compare_method]}", "false", "false", "${copyfile[${index}][purge]}"),
        depth_search => recurse("${copyfile[${index}][recursion]}"),
        file_select  => by_name("${copyfile[${index}][exclude_include]}"),
        perms        => mog(
                            "${copyfile[${index}][perm]}",
                            "${copyfile[${index}][owner]}",
                            "${copyfile[${index}][group]}"
                           ),
        comment      => "Enforce content of ${copyfile[${index}][destination]} based on the content on the Rudder server with ${copyfile[${index}][compare_method]} method with inclusion of '${copyfile[${index}][exclude_include]}'",
        classes      => rudder_common_classes("copy_file_${index}"),
        ifvarclass   => "(!exist_${index}|!is_file_${index}).need_inclusion_${index}";

    # If it s a file, the depth_search prevents from enforcing the file content
    # Besides it is possible to specify suid or sgid only for a file since this
    # is too dangerous to apply suid or sgid recursively and only copy an empty
    # directory does not make sense.
    # Don't take purge in account as well.
      "${copyfile[${index}][destination]}"
        copy_from  => rudder_copy_from("&SHARED_FILES_FOLDER&/${copyfile[${index}][name]}", "${server_info.cfserved}", "${copyfile[${index}][compare_method]}", "false", "false", "false"),
        perms      => mog(
                          "${extended_modes_${index}}${copyfile[${index}][perm]}",
                          "${copyfile[${index}][owner]}",
                          "${copyfile[${index}][group]}"
                         ),
        comment    => "Enforce content of file ${copyfile[${index}][destination]} based on the content on the Rudder server with ${copyfile[${index}][compare_method]} method with exclusion of '${copyfile[${index}][exclude_include]}'",
        classes    => rudder_common_classes("copy_file_${index}"),
        ifvarclass => "exist_${index}.is_file_${index}";

  methods:

      "any" usebundle => file_check_symlink(dirname("${copyfile[${index}][destination]}"));

    pass3.(!is_valid)::
      "any" usebundle => rudder_common_report("copyFile", "result_error", "${copyfile[${index}][uuid]}", "Copy file", "${copyfile[${index}][name]}", "There is no shared folder on the Rudder Server, so it's not possible to copy a file from it");

    pass3.is_valid::
      "any" usebundle => rudder_common_report("copyFile", "result_success", "${copyfile[${index}][uuid]}", "Copy file", "${copyfile[${index}][name]}", "The content of the file(s) is valid"),
        ifvarclass => "copy_file_${index}_kept.!copy_file_${index}_repaired.!copy_file_${index}_error";

      "any" usebundle => rudder_common_report("copyFile", "result_repaired", "${copyfile[${index}][uuid]}", "Copy file", "${copyfile[${index}][name]}", "The content or permissions of the file(s) has been repaired"),
        ifvarclass => "copy_file_${index}_repaired.!copy_file_${index}_error";

      # Error conditons

      ## The destination is not an existing directory or symbolic link
      "any" usebundle => rudder_common_report("copyFile", "result_error", "${copyfile[${index}][uuid]}", "Copy file", "${copyfile[${index}][name]}", "The copy of the file failed: the destination (${copyfile[${index}][destination]}) is not stored in a valid directory"),
        ifvarclass => "copy_file_${index}_dest_notdir.file_check_symlink_${canon_dirname_${index}}_failed";

      ## File access denied
      "any" usebundle => rudder_common_report("copyFile", "result_error", "${copyfile[${index}][uuid]}", "Copy file", "${copyfile[${index}][name]}", "The copy of the file failed: access to ${copyfile[${index}][name]} denied by the server"),
        ifvarclass => "copy_file_${index}_denied";

      ## User does not exist
      "any" usebundle => rudder_common_report("copyFile", "result_error", "${copyfile[${index}][uuid]}", "Copy file", "${copyfile[${index}][name]}", "The permissions could not be applied on the file: user \"${copyfile[${index}][owner]}\" not found"),
        ifvarclass => "copy_file_${index}_user_absent";

      ## Group does not exist
      "any" usebundle => rudder_common_report("copyFile", "result_error", "${copyfile[${index}][uuid]}", "Copy file", "${copyfile[${index}][name]}", "The permissions could not be applied on the file: group \"${copyfile[${index}][group]}\" not found"),
        ifvarclass => "copy_file_${index}_group_absent";

      ## Generic failure
      "any" usebundle => rudder_common_report("copyFile", "result_error", "${copyfile[${index}][uuid]}", "Copy file", "${copyfile[${index}][name]}", "The content or permissions of the file(s) could not have been repaired (file not found?)"),
        ifvarclass => "copy_file_${index}_error.!copy_file_${index}_dest_notdir.!copy_file_${index}_denied.!copy_file_${index}_user_absent.!copy_file_${index}_group_absent";

    #posthook reports
      "any" usebundle => rudder_common_report("copyFile", "result_success", "${copyfile[${index}][uuid]}", "Post-modification hook", "${copyfile[${index}][name]}", "No post-hook command for ${copyfile[${index}][destination]} was defined, not executing"),
        ifvarclass => "!execute_command_${index}";

      "any" usebundle => rudder_common_report("copyFile", "result_success", "${copyfile[${index}][uuid]}", "Post-modification hook", "${copyfile[${index}][name]}", "${copyfile[${index}][destination]} was already in the desired state, so no command was executed"),
        ifvarclass => "execute_command_${index}.!copy_file_${index}_error.!copy_file_${index}_repaired.copy_file_${index}_kept";

      "any" usebundle => rudder_common_report("copyFile", "result_success", "${copyfile[${index}][uuid]}", "Post-modification hook", "${copyfile[${index}][name]}", "The post-hook command for ${copyfile[${index}][destination]} was correctly executed"),
        ifvarclass => "execute_command_${index}.copyfile_posthook_${index}_command_run_ok";

      "any" usebundle => rudder_common_report("copyFile", "result_error", "${copyfile[${index}][uuid]}", "Post-modification hook", "${copyfile[${index}][name]}", "The post-hook command for ${copyfile[${index}][destination]} couldn't be executed"),
        ifvarclass => "execute_command_${index}.copyfile_posthook_${index}_command_run_failed";

      # A copy_from + perms could result in any combinaision of success/repaired/failed, so we have to cover the failed.modified which results in no copy
      "any" usebundle => rudder_common_report("copyFile", "result_error", "${copyfile[${index}][uuid]}", "Post-modification hook", "${copyfile[${index}][name]}", "${copyfile[${index}][destination]} couldn't be copied, so the post-hook command is not executed"),
        ifvarclass => "execute_command_${index}.copy_file_${index}_error";

  commands:
      "${copyfile[${index}][posthook]}"
        contain    => in_shell,
        classes    => if_else("copyfile_posthook_${index}_command_run_ok", "copyfile_posthook_${index}_command_run_failed"),
        ifvarclass => "execute_command_${index}.copy_file_${index}_repaired.!copy_file_${index}_error",
        comment    => "Execute the posthook command if a file was changed";

}
