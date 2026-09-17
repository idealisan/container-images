<?php
/**
 * wp-multisite-setup.php — CLI helper for the multisite-wp-sqlite image.
 *
 * Called by multisite-entrypoint.sh ONLY (never reachable from the web):
 *
 *   php wp-multisite-setup.php install
 *       Headless first boot: installs the single site with wp_install()
 *       (needs WORDPRESS_ADMIN_USER / WORDPRESS_ADMIN_PASSWORD /
 *       WORDPRESS_ADMIN_EMAIL, optional WORDPRESS_URL / WORDPRESS_SITE_TITLE),
 *       then populates the network. One pass, no install wizard, no restart.
 *
 *   php wp-multisite-setup.php populate-network
 *       Converts an already-installed single site (e.g. created through the
 *       ordinary install wizard) into a network.
 *
 * The populate step mirrors wp-admin/network.php "Network Setup" step 2
 * exactly: assign the ms_global table names to $wpdb, install_network()
 * (dbDelta of the global schema), then populate_network(). It works on the
 * SQLite plugin's db.php drop-in because everything boots through wp-load.
 */

if ( PHP_SAPI !== 'cli' ) {
	exit( 1 );
}

$docroot = '/var/www/html';
if ( ! is_file( $docroot . '/wp-load.php' ) ) {
	fwrite( STDERR, "wp-multisite-setup: WordPress not found in {$docroot}\n" );
	exit( 1 );
}

function msd_truthy( $value ) {
	return in_array( strtolower( trim( (string) $value ) ), array( '1', 'true', 'yes', 'on' ), true );
}

function msd_domain_from_url( $url ) {
	$p = parse_url( (string) $url );
	if ( empty( $p['host'] ) ) {
		return '';
	}
	$domain = strtolower( $p['host'] );
	// Core ms-settings only strips :80/:443 from HTTP_HOST, so any other
	// port must stay part of the network domain to keep lookups consistent.
	if ( ! empty( $p['port'] ) && ! in_array( $p['port'], array( 80, 443 ), true ) ) {
		$domain .= ':' . $p['port'];
	}
	return $domain;
}

$email = '';

$mode = isset( $argv[1] ) ? $argv[1] : '';

if ( 'install' === $mode ) {
	// WP_INSTALLING must be defined before wp-load so the empty database
	// does not trigger the "not installed" die inside wp-settings.php.
	define( 'WP_INSTALLING', true );

	$user     = getenv( 'WORDPRESS_ADMIN_USER' );
	$password = getenv( 'WORDPRESS_ADMIN_PASSWORD' );
	$email    = getenv( 'WORDPRESS_ADMIN_EMAIL' );
	$title    = getenv( 'WORDPRESS_SITE_TITLE' );
	$url      = getenv( 'WORDPRESS_URL' );

	if ( ! $user || ! $password || ! $email ) {
		fwrite( STDERR, "wp-multisite-setup: install mode needs WORDPRESS_ADMIN_USER, WORDPRESS_ADMIN_PASSWORD and WORDPRESS_ADMIN_EMAIL\n" );
		exit( 1 );
	}

	require $docroot . '/wp-load.php';
	require ABSPATH . 'wp-admin/includes/upgrade.php';

	if ( is_blog_installed() ) {
		fwrite( STDERR, "wp-multisite-setup: site already installed, skipping wp_install()\n" );
	} else {
		if ( ! $title ) {
			$title = 'My WordPress Network';
		}
		$result = wp_install( $title, $user, $email, 1, '', $password, '' );
		if ( empty( $result['user_id'] ) ) {
			fwrite( STDERR, "wp-multisite-setup: wp_install() failed\n" );
			exit( 1 );
		}
		echo "wp-multisite-setup: single site installed (admin user id {$result['user_id']})\n";
		if ( $url ) {
			// wp_guess_url() cannot see the real host on the CLI; point the
			// site at the requested URL instead of the guessed default.
			update_option( 'siteurl', $url );
			update_option( 'home', $url );
		}
	}
} elseif ( 'populate-network' === $mode ) {
	require $docroot . '/wp-load.php';
	require ABSPATH . 'wp-admin/includes/upgrade.php';

	if ( ! is_blog_installed() ) {
		fwrite( STDERR, "wp-multisite-setup: WordPress is not installed yet — finish the install wizard first, then restart the container\n" );
		exit( 1 );
	}
} else {
	fwrite( STDERR, "usage: php wp-multisite-setup.php install|populate-network\n" );
	exit( 1 );
}

// ---- populate the network (shared by both modes) ----

if ( is_multisite() ) {
	echo "wp-multisite-setup: MULTISITE already enabled, nothing to do\n";
	exit( 0 );
}

$domain = getenv( 'WORDPRESS_DOMAIN_CURRENT_SITE' );
if ( ! $domain ) {
	$domain = msd_domain_from_url( getenv( 'WORDPRESS_URL' ) );
}
if ( ! $domain ) {
	$domain = msd_domain_from_url( get_option( 'siteurl' ) );
}
if ( ! $domain ) {
	$domain = 'localhost';
	fwrite( STDERR, "wp-multisite-setup: WARNING: could not derive the network domain, falling back to '{$domain}' (set WORDPRESS_DOMAIN_CURRENT_SITE to override)\n" );
}

if ( ! $email ) {
	$email = get_option( 'admin_email' );
}
$sitename = get_option( 'blogname' );
if ( ! $sitename ) {
	$sitename = $domain;
}
$subdomain = msd_truthy( getenv( 'WORDPRESS_SUBDOMAIN_INSTALL' ) );

// $wpdb->site / blogs / sitemeta / ... are undefined on a single-site
// install; point them at the ms_global table names before install_network().
foreach ( $wpdb->tables( 'ms_global' ) as $table => $prefixed_table ) {
	$wpdb->$table = $prefixed_table;
}

install_network();
$result = populate_network( 1, $domain, $email, $sitename, '/', $subdomain );

if ( is_wp_error( $result ) ) {
	if ( 'siteid_exists' === $result->get_error_code() ) {
		echo "wp-multisite-setup: network already populated, nothing to do\n";
		exit( 0 );
	}
	fwrite( STDERR, 'wp-multisite-setup: populate_network failed: ' . $result->get_error_message() . "\n" );
	exit( 1 );
}

echo 'wp-multisite-setup: network populated (domain \'' . $domain . '\', ' . ( $subdomain ? 'subdomain' : 'subdirectory' ) . " mode)\n";
exit( 0 );
