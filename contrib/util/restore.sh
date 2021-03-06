#!/bin/bash

# Copyright (C) 2008-2010 Rod Roark <rod@sunsetsystems.com>
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This is for restoring a backup created by the "Backup" option
# in LibreEHR's administration menu, which invokes
# interface/main/backup.php.
#
# Xdialog is supported if available... dialog support is also in
# here but is disabled, as it was found to be ugly and clumsy.

DLGCMD=""
NOBUTTONS=""
DEFAULTNO=""
LEFT=""
if [ ! -z "$DISPLAY" -a ! -z "`which Xdialog`" ]; then
  DLGCMD="Xdialog"
  NOBUTTONS="--no-buttons"
  DEFAULTNO="--default-no"
  LEFT="--left"
# elif [ ! -z `which dialog` ]; then
#   DLGCMD="dialog"
fi

dlg_msg() {
  if [ ! -z "$DLGCMD" ]; then
    local MSG="$1"
    shift
    while [ ! -z "$1" ]; do
      MSG="$MSG\n$1"
      shift
    done
    $DLGCMD --title 'LibreEHR Restore' $LEFT --msgbox "$MSG" 0 0
    return 0
  fi
  while [ ! -z "$1" ]; do
    echo "$1"
    shift
  done
}

dlg_info() {
  if [ ! -z "$DLGCMD" ]; then
    if [ "$DLGCMD" = "Xdialog" ]; then
      echo "$1"
    fi
    $DLGCMD --title 'LibreEHR Restore' $LEFT --infobox "$1" 0 0
    return 0
  fi
  echo "$1"
}

dlg_fselect() {
  if [ ! -z "$DLGCMD" ]; then
    exec 3>&1
    RESULT=`$DLGCMD --title 'LibreEHR Restore' --backtitle "$1" $NOBUTTONS --fselect $HOME/ 0 70 2>&1 1>&3`
    CODE=$?
    exec 3>&-
    if [ $CODE -eq 0 ]; then
      return 0
    fi
    echo $RESULT
    exit 1
  fi
  echo " "
  read -e -p "$1: " RESULT
}

dlg_yesno() {
  if [ ! -z "$DLGCMD" ]; then
    local MSG="$1"
    shift
    while [ ! -z "$1" ]; do
      MSG="$MSG\n$1"
      shift
    done
    $DLGCMD --title 'LibreEHR Restore' $DEFAULTNO $LEFT --yesno "$MSG" 0 0
    CODE=$?
    exec 3>&-
    if [ $CODE -eq 0 ]; then
      RESULT="1"
    elif [ $CODE -eq 1 ]; then
      RESULT="0"
    else
      exit 1
    fi
    return 0
  fi
  echo " "
  while [ ! -z "$2" ]; do
    echo "$1"
    shift
  done
  read -e -p "$1 [N/y] " RESULT
  RESULT=`expr "$RESULT" : "[yY]"`
  return 0
}

dlg_input() {
  if [ ! -z "$DLGCMD" ]; then
    exec 3>&1
    RESULT=`$DLGCMD --title 'LibreEHR Restore' $LEFT --inputbox "$1" 0 0 2>&1 1>&3`
    CODE=$?
    exec 3>&-
    if [ $CODE -eq 0 ]; then
      return 0
    fi
    echo $RESULT
    exit 1
  fi
  echo " "
  read -e -p "$1 " RESULT
}

dlg_blank_line() {
  if [ -z "$DLGCMD" ]; then
    echo " "
  fi
}

dlg_msg "WARNING: This script is experimental." "It may have serious bugs or omissions." "Use it at your own risk!"

BAKDIR=/tmp/emr_backup

if [ $UID -ne 0 ]; then
  dlg_msg "Error: This script must be executed with root privileges."
  exit 1
fi

# Create and change to a clean scratch directory.
rm -rf $BAKDIR
mkdir  $BAKDIR
if [ $? -ne 0 ]; then
  dlg_msg "Error: Cannot create directory '$BAKDIR'."
  exit 1
fi

dlg_msg "Now you will be asked for the backup file." "By default this is named emr_backup.tar, although you may have saved it as something else."

LOOKING=1
while [ $LOOKING -eq 1 ]; do
  dlg_fselect "Enter path/name of backup file"
  TARFILE=$RESULT
  dlg_blank_line
  if [ ! -f $TARFILE ]; then
    dlg_msg "Error: '$TARFILE' is not found or is not a file."
  else
    # Extract the backup tarball into the scratch directory.
    dlg_info "Extracting $TARFILE ..."
    cd $BAKDIR
    tar -xf $TARFILE
    if [ $? -ne 0 ]; then
      dlg_msg "Error: tar could not extract '$TARFILE'."
    else
      LOOKING=0
    fi
  fi
done

# Extract the LibreEHR web directory tree.
dlg_info "Extracting $BAKDIR/libreehr.tar.gz ..."
mkdir libreehr
cd libreehr
tar zxf ../libreehr.tar.gz
if [ $? -ne 0 ]; then
  dlg_msg "Error: tar could not extract '$BAKDIR/libreehr.tar.gz'."
  exit 1
fi

OEDIR=/var/www/libreehr

# Get the Site ID, it should be the only site backed up.
SITEID=`ls -1 sites | head -n 1`

# Get various parameters from the extracted files.
OEDBNAME=`grep '^\$dbase' sites/$SITEID/sqlconf.php | cut -d \' -f 2 | cut -d \" -f 2`
OEDBUSER=`grep '^\$login' sites/$SITEID/sqlconf.php | cut -d \' -f 2 | cut -d \" -f 2`
OEDBPASS=`grep '^\$pass'  sites/$SITEID/sqlconf.php | cut -d \' -f 2 | cut -d \" -f 2`
SLDBNAME=''
# SL support is becoming obsolete, but we're leaving it in for now.
if [ -f ../sql-ledger.sql ]; then
  SLDBNAME=`grep '^\$sl_dbname' interface/globals.php | cut -d \' -f 2`
  SLDBUSER=`grep '^\$sl_dbuser' interface/globals.php | cut -d \' -f 2`
  SLDBPASS=`grep '^\$sl_dbpass' interface/globals.php | cut -d \' -f 2`
fi
# Likewise, external phpGACL is discouraged because it will not work
# with multiple sites.
GADIR=''
GACONFIGDIR=''
GADBNAME=''
if [ -f ../phpgacl.tar.gz ]; then
  GADIR=`grep '^\s*\$phpgacl_location' library/acl.inc | cut -d \" -f 2`
  GACONFIGDIR="$GADIR"
  mkdir ../phpgacl
  cd    ../phpgacl
  dlg_info "Extracting $BAKDIR/phpgacl.tar.gz ..."
  tar zxf ../phpgacl.tar.gz
  if [ $? -ne 0 ]; then
    dlg_msg "Error: tar could not extract '$BAKDIR/phpgacl.tar.gz'."
    exit 1
  fi
  if [ -f ../phpgacl.sql.gz ]; then
    GADBNAME=`grep '^\s*var \$_db_name'     gacl.class.php | cut -d \' -f 2`
    GADBUSER=`grep '^\s*var \$_db_user'     gacl.class.php | cut -d \' -f 2`
    GADBPASS=`grep '^\s*var \$_db_password' gacl.class.php | cut -d \' -f 2`
  fi
elif [ -e gacl ]; then
  grep '^\s*\$phpgacl_location' library/acl.inc > /dev/null
  if [ $? -eq 0 ]; then
    GACONFIGDIR="$OEDIR/gacl"
    if [ -f ../phpgacl.sql.gz ]; then
      cd gacl
      GADBNAME=`grep '^\s*var \$_db_name'     gacl.class.php | cut -d \' -f 2`
      GADBUSER=`grep '^\s*var \$_db_user'     gacl.class.php | cut -d \' -f 2`
      GADBPASS=`grep '^\s*var \$_db_password' gacl.class.php | cut -d \' -f 2`
      cd ..
    fi
  fi
fi
#
SLDIR=''
if [ -f ../sql-ledger.tar.gz ]; then
  SLDIR=`dirname $OEDIR`/sql-ledger
fi

dlg_yesno "Do you want to specify site ID, locations or database names for the restore?"

CHANGES=$RESULT
OLDSITEID=$SITEID

dlg_blank_line

if [ $CHANGES -gt 0 ]; then
  dlg_msg "Current values are shown in [brackets]. Just hit Enter to leave them as-is."
  dlg_input "Site ID [$SITEID]? "
  if [ ! -z "$RESULT" ]; then SITEID="$RESULT"; fi
  dlg_input "LibreEHR database name [$OEDBNAME]? "
  if [ ! -z "$RESULT" ]; then OEDBNAME="$RESULT"; fi
  dlg_input "LibreEHR database user [$OEDBUSER]? "
  if [ ! -z "$RESULT" ]; then OEDBUSER="$RESULT"; fi
  dlg_input "LibreEHR database password [$OEDBPASS]? "
  if [ ! -z "$RESULT" ]; then OEDBPASS="$RESULT"; fi
  if [ ! -z "$GADBNAME" ]; then
    dlg_input "phpGACL database name [$GADBNAME]? "
    if [ ! -z "$RESULT" ]; then GADBNAME="$RESULT"; fi
    OLDGADBUSER="$GADBUSER"
    LOOKING=1
    while [ $LOOKING -eq 1 ]; do
      dlg_input "phpGACL database user [$GADBUSER]? "
      if [ ! -z "$RESULT" ]; then GADBUSER="$RESULT"; fi
      if [ "$GADBUSER" = "$SLDBUSER" ]; then
        dlg_msg "Error: LibreEHR and phpGACL have separate databases but the same user name." "They must be different user names."
        GADBUSER="$OLDGADBUSER"
      else
        LOOKING=0
      fi
    done
    dlg_input "phpGACL database password [$GADBPASS]? "
    if [ ! -z "$RESULT" ]; then GADBPASS="$RESULT"; fi
  fi
  if [ ! -z "$SLDBNAME" ]; then
    OLDSLDBNAME="$SLDBNAME"
    dlg_input "SQL-Ledger database name [$SLDBNAME]? "
    if [ ! -z "$RESULT" ]; then SLDBNAME="$RESULT"; fi
    dlg_input "SQL-Ledger database user [$SLDBUSER]? "
    if [ ! -z "$RESULT" ]; then SLDBUSER="$RESULT"; fi
    dlg_input "SQL-Ledger database password [$SLDBPASS]? "
    if [ ! -z "$RESULT" ]; then SLDBPASS="$RESULT"; fi
  fi
  OLDOEDIR="$OEDIR"
  dlg_input "New LibreEHR web directory [$OEDIR]? "
  if [ ! -z "$RESULT" ]; then OEDIR="$RESULT"; fi
  if [ ! -z "$GADIR" ]; then
    OLDGADIR="$GADIR"
    dlg_input "New phpGACL web directory [$GADIR]? "
    if [ ! -z "$RESULT" ]; then GADIR="$RESULT"; fi
  fi
  if [ ! -z "$SLDIR" ]; then
    OLDSLDIR="$SLDIR"
    dlg_input "New SQL-Ledger web directory [$SLDIR]? "
    if [ ! -z "$RESULT" ]; then SLDIR="$RESULT"; fi
    dlg_input "Previous SQL-Ledger web directory [$OLDSLDIR]? "
    if [ ! -z "$RESULT" ]; then OLDSLDIR="$RESULT"; fi
  fi
  #
fi

# Patch up $GACONFIGDIR in case it was changed.
if [ -z "$GADIR" ]; then
  if [ ! -z "$GACONFIGDIR" ]; then
    GACONFIGDIR="$OEDIR/gacl"
  fi
else
  GACONFIGDIR="$GADIR"
fi

# If phpgacl has its own database, make sure the database user is not the
# same as for libreehr.  This is to prevent screwups caused by persistent
# database connections in PHP.
if [ ! -z "$GADBNAME" ]; then
  if [ "$GADBUSER" = "$OEDBUSER" ]; then
    dlg_msg "Error: LibreEHR and phpGACL have separate databases but the same user name." "They must be different user names."
    exit 1
  fi
fi

# The following sanity checks are an attempt to avoid disastrous results
# from mistakes in entry of directory path names.

TRASH=`expr "$OEDIR" : "[/]"`
if [ $TRASH -ne 1 ]; then
  dlg_msg "Error: The LibreEHR directory path '$OEDIR' does not start with '/'."
  exit 1
fi
if [ -e "$OEDIR" -a ! -e "$OEDIR/interface/globals.php" ]; then
  dlg_msg "Error: $OEDIR already exists but does not look like an LibreEHR directory." "If you are really sure you want to replace it, please remove it first."
  exit 1
fi

if [ ! -z "$GADIR" ]; then
  TRASH=`expr "$GADIR" : "[/]"`
  if [ $TRASH -ne 1 ]; then
    dlg_msg "Error: The phpGACL directory path '$GADIR' does not start with '/'."
    exit 1
  fi
  if [ -e "$GADIR" -a ! -e "$GADIR/gacl.class.php" ]; then
    dlg_msg "Error: $GADIR already exists but does not look like a phpGACL directory." "If you are really sure you want to replace it, please remove it first."
    exit 1
  fi
fi

if [ ! -z "$SLDIR" ]; then
  TRASH=`expr "$SLDIR" : "[/]"`
  if [ $TRASH -ne 1 ]; then
    dlg_msg "Error: The SQL-Ledger directory path '$SLDIR' does not start with '/'."
    exit 1
  fi
  if [ -e "$SLDIR" -a ! -e "$SLDIR/setup.pl" ]; then
    dlg_msg "Error: $SLDIR already exists but does not look like a SQL-Ledger directory." "If you are really sure you want to replace it, please remove it first."
    exit 1
  fi
fi

if [ -e "$OEDIR" -a ! -e "$OEDIR/sites" ]; then
  dlg_msg "Error: Directory '$OEDIR/sites' is missing - old release needs removal?"
  exit 1
fi

if [ -e "$OEDIR/sites/$SITEID" ]; then
  dlg_msg "Error: Site '$SITEID' already exists in '$OEDIR/sites'."
  exit 1
fi

COLLATE="utf8_general_ci"
dlg_msg "If you have a particular requirement for the UTF-8 collation to use, " \
  "then please specify it here.  Hit Enter to accept the default '$COLLATE'." \
  "Enter 'none' if you do not want UTF-8."
dlg_input "UTF-8 collation [$COLLATE]? "
if [ ! -z "$RESULT" ]; then COLLATE="$RESULT"; fi
TRASH=`expr "$COLLATE" : "[uU]"`
if [ $TRASH -ne 1 ]; then
  COLLATE=""
fi

# Ask the user to do final sanity checking.
#
MARGS="\"Your Site ID will be '$SITEID'.\""
if [ -e "$OEDIR" ]; then
  MARGS="$MARGS \"Only site-specific files will be restored to '$OEDIR/sites/$SITEID' in the existing LibreEHR web directory.\""
else
  MARGS="$MARGS \"I will install a new LibreEHR web directory '$OEDIR' from the backup.\""
fi
MARGS="$MARGS \"I will restore the LibreEHR database backup to the MySQL database '$OEDBNAME'.\""
MARGS="$MARGS \"The LibreEHR database user will be '$OEDBUSER' with password '$OEDBPASS'.\""
if [ ! -z "$GADBNAME" ]; then
  MARGS="$MARGS \"I will restore the phpGACL database backup to the MySQL database '$GADBNAME'.\""
  MARGS="$MARGS \"The phpGACL database user will be '$GADBUSER' with password '$GADBPASS'.\""
fi
if [ -z "$COLLATE" ]; then
  MARGS="$MARGS \"MySQL will use its default character set and collation.\""
else
  MARGS="$MARGS \"MySQL will use character set 'utf8' with collation '$COLLATE'.\""
fi
if [ ! -z "$SLDBNAME" ]; then
  MARGS="$MARGS \"I will restore the SQL-Ledger database backup to the PostgreSQL database '$SLDBNAME'.\""
  MARGS="$MARGS \"The SQL-Ledger database user will be '$SLDBUSER' with password '$SLDBPASS'.\""
fi
if [ ! -z "$GADIR" ]; then
  MARGS="$MARGS \"I will copy the phpGACL web directory backup to '$GADIR'.\""
fi
if [ ! -z "$SLDIR" ]; then
  MARGS="$MARGS \"I will copy the SQL-Ledger web directory backup to '$SLDIR'.\""
fi
MARGS="$MARGS \" \""
MARGS="$MARGS \"Please check the above very carefully!\""
MARGS="$MARGS \"Any existing databases and directories matching these names will be DESTROYED.\""
MARGS="$MARGS \"Do you wish to continue?\""
#
eval "dlg_yesno $MARGS"
if [ $RESULT -ne 1 ]; then
  exit 1
fi

dlg_blank_line

dlg_msg "In order to create MySQL databases and users on this computer, I will need to" \
        "log into MySQL as its 'root' user.  The next question asks for the MySQL root" \
        "user's password for this server, the one that you are restoring to.  This is"  \
        "a MySQL password, not a system login password.  It might be blank."
dlg_input 'Enter the password, if any, for the MySQL root user:'
MYROOTPASS="$RESULT"

dlg_blank_line

dlg_info "Dropping old LibreEHR database if it exists ..."
mysqladmin --password="$MYROOTPASS" --force drop $OEDBNAME 2> /dev/null

dlg_info "Restoring LibreEHR database ..."
cd $BAKDIR
gunzip libreehr.sql.gz
if [ $? -ne 0 ]; then
  dlg_msg "Error: Could not decompress '$BAKDIR/libreehr.sql.gz'."
  exit 1
fi

if [ -z $COLLATE ]; then
  TRASH="CREATE DATABASE $OEDBNAME"
else
  TRASH="CREATE DATABASE $OEDBNAME CHARACTER SET utf8 COLLATE $COLLATE"
fi
mysql --password="$MYROOTPASS" --execute "$TRASH"
if [ $? -ne 0 ]; then
  dlg_msg "Error creating MySQL database with '$TRASH'."
  exit 1
fi

mysql --password="$MYROOTPASS" --execute "GRANT ALL PRIVILEGES ON $OEDBNAME.* TO '$OEDBUSER'@'localhost' IDENTIFIED BY '$OEDBPASS'" $OEDBNAME
mysql --user=$OEDBUSER --password="$OEDBPASS" $OEDBNAME < libreehr.sql
if [ $? -ne 0 ]; then
  dlg_msg "Error: Restore to database '$OEDBNAME' failed."
  exit 1
fi

if [ ! -z "$GADBNAME" ]; then
  dlg_info "Dropping old phpGACL database if it exists ..."
  mysqladmin --password="$MYROOTPASS" --force drop $GADBNAME 2> /dev/null
  dlg_info "Restoring phpGACL database ..."
  cd $BAKDIR
  gunzip phpgacl.sql.gz
  if [ $? -ne 0 ]; then
    dlg_msg "Error: Could not decompress '$BAKDIR/phpgacl.sql.gz'."
    exit 1
  fi

  if [ -z $COLLATE ]; then
    TRASH="CREATE DATABASE $GADBNAME"
  else
    TRASH="CREATE DATABASE $GADBNAME CHARACTER SET utf8 COLLATE $COLLATE"
  fi
  mysql --password="$MYROOTPASS" --execute "$TRASH"
  if [ $? -ne 0 ]; then
    dlg_msg "Error creating MySQL database with '$TRASH'."
    exit 1
  fi

  mysql --password="$MYROOTPASS" --execute "GRANT ALL PRIVILEGES ON $GADBNAME.* TO '$GADBUSER'@'localhost' IDENTIFIED BY '$GADBPASS'" $GADBNAME
  mysql --user=$GADBUSER --password="$GADBPASS" $GADBNAME < phpgacl.sql
  if [ $? -ne 0 ]; then
    dlg_msg "Error: Restore to database '$GADBNAME' failed."
    exit 1
  fi
fi

if [ ! -z "$SLDBNAME" ]; then
  # Avoid local domain connections for the sql-ledger user, because a
  # default postgresql configuration is likely set to require "ident"
  # authentication for them.
  MYPGHOST=localhost
  if [ ! -z "$PGHOST" ]; then
    MYPGHOST="$PGHOST";
  fi
  #
  unset PGUSER
  unset PGPASSWORD
  dlg_info "Restarting Apache to close persistent database connections ..."
  apache2ctl graceful
  dlg_info "Dropping old SQL-Ledger database if it exists ..."
  sudo -u postgres psql --command "DROP DATABASE \"$SLDBNAME\"" template1 2> /dev/null
  dlg_info "Creating procedural language and database user ..."
  sudo -u postgres createlang plpgsql template1 2> /dev/null
  sudo -u postgres psql --command "DROP ROLE \"$SLDBUSER\"" template1 2> /dev/null
  #
  # This next part merits some comment. The database is best loaded by the
  # sql-ledger user, otherwise we will have the nasty task of granting that
  # user access to all of its tables individually, which PostgreSQL does not
  # provide a convenient way of doing.  However superuser privilege is needed
  # to properly restore the dump.  Therefore we give the new role superuser
  # privilege now and revoke it after the restore is done.
  #
  sudo -u postgres psql --command "CREATE ROLE \"$SLDBUSER\" PASSWORD '$SLDBPASS' SUPERUSER CREATEDB CREATEROLE INHERIT LOGIN" template1
  dlg_info "Creating and restoring SQL-Ledger database ..."
  export PGUSER="$SLDBUSER"
  export PGPASSWORD="$SLDBPASS"
  psql -h $MYPGHOST --command "CREATE DATABASE \"$SLDBNAME\" WITH TEMPLATE template0" template1
  if [ $? -ne 0 ]; then
    dlg_msg "Error: Could not create PostgreSQL database '$SLDBNAME'."
    exit 1
  fi
  pg_restore -h $MYPGHOST --no-owner --dbname=$SLDBNAME sql-ledger.sql
  if [ $? -ne 0 ]; then
    dlg_msg "Error: Restore to database '$SLDBNAME' failed."
    exit 1
  fi
  unset PGUSER
  unset PGPASSWORD
  sudo -u postgres psql --command "ALTER ROLE \"$SLDBUSER\" NOSUPERUSER" template1
  if [ $? -ne 0 ]; then
    dlg_info "Warning: ALTER ROLE failed."
  fi
  sudo -u postgres psql --command "ANALYZE" $SLDBNAME
fi

if [ -e "$OEDIR" ]; then
  dlg_info "Restoring site subdirectory ..."
  mv $BAKDIR/libreehr/sites/$OLDSITEID $OEDIR/sites/$SITEID
  if [ $? -ne 0 ]; then
    dlg_msg "Error: Cannot create directory '$OEDIR/sites/$SITEID'."
    exit 1
  fi
else
  dlg_info "Restoring LibreEHR web directory tree ..."
  mv $BAKDIR/libreehr $OEDIR
  if [ $? -ne 0 ]; then
    dlg_msg "Error: Cannot create directory '$OEDIR'."
    exit 1
  fi
fi
#
if [ $CHANGES -gt 0 ]; then
  if [ ! -z "$SLDIR" ]; then
    dlg_info "Modifying $OEDIR/interface/globals.php ..."
    cd $OEDIR/interface
    mv -f globals.php globals.php.old
    sed "s^sl_dbname *= '.*'^sl_dbname = '$SLDBNAME'^" globals.php.old | \
    sed "s^sl_dbuser *= '.*'^sl_dbuser = '$SLDBUSER'^"                 | \
    sed "s^sl_dbpass *= '.*'^sl_dbpass = '$SLDBPASS'^"                   \
    > globals.php
  fi
  #
  dlg_info "Modifying $OEDIR/sites/$SITEID/sqlconf.php ..."
  cd $OEDIR/sites/$SITEID
  mv sqlconf.php sqlconf.php.old
  sed "s^dbase\s*=\s*['\"].*['\"]^dbase\t= '$OEDBNAME'^" sqlconf.php.old | \
  sed "s^login\s*=\s*['\"].*['\"]^login\t= '$OEDBUSER'^"                 | \
  sed "s^pass\s*=\s*['\"].*['\"]^pass\t= '$OEDBPASS'^" > sqlconf.php
  #
  # Logic to fix the path to ws_server.pl in includes/config.php was removed.
  # Not gonna worry about this because SL is deprecated, the old logic was not
  # very robust, and this can be fixed up manually easily enough.
fi

if [ ! -z "$GADIR" ]; then
  dlg_info "Restoring phpGACL web directory tree ..."
  mkdir -p $GADIR
  rm -rf $GADIR
  mv $BAKDIR/phpgacl $GADIR
  if [ $? -ne 0 ]; then
    dlg_msg "Error: Cannot create directory '$GADIR'."
    exit 1
  fi
  #
  if [ $CHANGES -gt 0 ]; then
    dlg_info "Modifying $OEDIR/library/acl.inc ..."
    cd $OEDIR/library
    mv -f acl.inc acl.inc.old
    sed "s^phpgacl_location *= *\"/.*\"^phpgacl_location = \"$GADIR\"^" acl.inc.old > acl.inc
  fi
fi

if [ ! -z "$GACONFIGDIR" -a $CHANGES -gt 0 -a ! -z "$GADBNAME" ]; then
  dlg_info "Modifying $GACONFIGDIR/gacl.class.php ..."
  cd $GACONFIGDIR
  mv -f gacl.class.php gacl.class.php.old
  sed "s^db_name *= *'.*'^db_name = '$GADBNAME'^" gacl.class.php.old | \
  sed "s^db_user *= *'.*'^db_user = '$GADBUSER'^"                    | \
  sed "s^db_password *= *'.*'^db_password = '$GADBPASS'^" > gacl.class.php
  #
  dlg_info "Modifying $GACONFIGDIR/gacl.ini.php ..."
  cd $GACONFIGDIR
  mv -f gacl.ini.php gacl.ini.php.old
  sed "s^db_name[ \t]*= *\".*\"^db_name\t\t\t= \"$GADBNAME\"^" gacl.ini.php.old | \
  sed "s^db_user[ \t]*= *\".*\"^db_user\t\t\t= \"$GADBUSER\"^"                  | \
  sed "s^db_password[ \t]*= *\".*\"^db_password\t\t= \"$GADBPASS\"^" > gacl.ini.php
fi

if [ ! -z "$SLDIR" ]; then
  dlg_info "Restoring SQL-Ledger web directory tree ..."
  mkdir -p $SLDIR
  rm -rf $SLDIR
  mkdir $SLDIR
  cd $SLDIR
  if [ $? -ne 0 ]; then
    dlg_msg "Error: Creating $SLDIR failed."
    exit 1
  fi
  tar zxf $BAKDIR/sql-ledger.tar.gz
  if [ $? -ne 0 ]; then
    dlg_msg "Error: Extracting '$BAKDIR/sql-ledger.tar.gz' failed."
    exit 1
  fi
  #
  if [ $CHANGES -gt 0 ]; then
    # SQL-Ledger stores passwords in an obfuscated form.
    SLDBHASH=`perl -e "print pack u, '$SLDBPASS'"`
    #
    dlg_info "Modifying $SLDIR/ws_server.pl ..."
    cd $SLDIR
    mv -f ws_server.pl ws_server.pl.old
    sed "s^$OLDSLDIR^$SLDIR^" ws_server.pl.old > ws_server.pl
    chmod a+x ws_server.pl
    #
    dlg_info "Modifying $SLDIR/users/admin.conf ..."
    cd $SLDIR/users
    cp -f admin.conf admin.conf.old
    sed "s^dbname => '.*'^dbname => '$SLDBNAME'^" admin.conf.old | \
    sed "s^dbuser => '.*'^dbuser => '$SLDBUSER'^"                | \
    sed "/dbpasswd =>/ c \  dbpasswd => '$SLDBHASH',"            | \
    sed "s^dbname=$OLDSLDBNAME^dbname=$SLDBNAME^" > admin.conf
    #
    dlg_info "Modifying $SLDIR/users/members ..."
    cd $SLDIR/users
    cp -f members members.old
    sed "s^dbname=.*^dbname=$SLDBNAME^g" members.old | \
    sed "s^dbuser=.*^dbuser=$SLDBUSER^g"             | \
    sed "/dbpasswd=/ c dbpasswd=$SLDBHASH" > members
  fi
fi

dlg_msg "All done."
