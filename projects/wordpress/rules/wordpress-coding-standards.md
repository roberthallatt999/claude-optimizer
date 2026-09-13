---
paths:
  - "**/*.php"
---

# WordPress Coding Standards

Follow these coding standards for all WordPress development.

## PHP Standards

### Indentation and Spacing
- Use **tabs** for indentation (not spaces) in PHP
- Put spaces after commas in function arguments
- Put spaces around operators: `$a = $b + $c;`
- No trailing whitespace
- Files should end with a newline

### Naming Conventions
```php
// Functions: lowercase with underscores
function theme_prefix_function_name() {}

// Classes: capitalized words
class Theme_Prefix_Class_Name {}

// Constants: uppercase with underscores
define('THEME_PREFIX_CONSTANT', 'value');

// Variables: lowercase with underscores
$my_variable = 'value';
```

### Brace Style
```php
// Opening brace on same line
if ($condition) {
    // code
} elseif ($other_condition) {
    // code
} else {
    // code
}

// Functions and classes
function my_function() {
    // code
}

class My_Class {
    public function method() {
        // code
    }
}
```

### Arrays
```php
// Short array syntax preferred
$array = [
    'key1' => 'value1',
    'key2' => 'value2',
];

// Multi-line for complex arrays
$args = [
    'post_type'      => 'post',
    'posts_per_page' => 10,
    'orderby'        => 'date',
];
```

## Security Rules

### ALWAYS Escape Output
```php
// HTML content
echo esc_html($variable);

// HTML attributes
<input value="<?php echo esc_attr($value); ?>">

// URLs
<a href="<?php echo esc_url($url); ?>">

// JavaScript
<script>var data = <?php echo wp_json_encode($data); ?>;</script>

// Translation with escaping
echo esc_html__('Text', 'textdomain');
echo esc_attr__('Attribute', 'textdomain');
```

### ALWAYS Sanitize Input
```php
// Text fields
$clean = sanitize_text_field($_POST['field']);

// Textarea
$clean = sanitize_textarea_field($_POST['textarea']);

// Email
$clean = sanitize_email($_POST['email']);

// URL
$clean = esc_url_raw($_POST['url']);

// Integer
$clean = absint($_POST['number']);

// Array of integers
$clean = array_map('absint', $_POST['ids']);
```

### ALWAYS Use Nonces
```php
// Creating nonce field in form
wp_nonce_field('action_name', 'nonce_field_name');

// Verifying nonce
if (!wp_verify_nonce($_POST['nonce_field_name'], 'action_name')) {
    wp_die('Security check failed');
}

// AJAX nonce
check_ajax_referer('action_name', 'nonce');
```

### ALWAYS Use Prepared Statements
```php
global $wpdb;

// NEVER do this
$wpdb->query("SELECT * FROM table WHERE id = " . $_GET['id']); // BAD!

// ALWAYS do this
$wpdb->get_results(
    $wpdb->prepare(
        "SELECT * FROM {$wpdb->prefix}table WHERE id = %d",
        absint($_GET['id'])
    )
);
```

### ALWAYS Check Capabilities
```php
if (!current_user_can('edit_posts')) {
    wp_die('You do not have permission to do this.');
}
```

## Database Rules

### Use WordPress Functions
```php
// Posts
get_posts($args);
WP_Query($args);
wp_insert_post($args);
wp_update_post($args);
wp_delete_post($post_id);

// Meta
get_post_meta($post_id, 'key', true);
update_post_meta($post_id, 'key', 'value');
delete_post_meta($post_id, 'key');

// Options
get_option('option_name');
update_option('option_name', 'value');
delete_option('option_name');

// Transients
get_transient('transient_name');
set_transient('transient_name', $value, HOUR_IN_SECONDS);
delete_transient('transient_name');
```

### Always Reset Post Data
```php
$query = new WP_Query($args);
while ($query->have_posts()) {
    $query->the_post();
    // ...
}
wp_reset_postdata(); // ALWAYS call this after custom queries
```

## Hook Priorities

```php
// Default priority is 10
add_action('init', 'my_function');

// Lower number = earlier execution
add_action('init', 'early_function', 5);

// Higher number = later execution
add_action('init', 'late_function', 20);

// Number of accepted arguments (default is 1)
add_filter('the_content', 'my_filter', 10, 2);
```

## Documentation

### Function Documentation
```php
/**
 * Short description.
 *
 * Long description if needed.
 *
 * @since 1.0.0
 *
 * @param string $param1 Description.
 * @param int    $param2 Description.
 * @return bool Description of return value.
 */
function theme_prefix_function($param1, $param2) {
    // ...
}
```

## Anti-Patterns to Avoid

1. **Don't modify core files** - Ever
2. **Don't use `query_posts()`** - Use `WP_Query` or `pre_get_posts`
3. **Don't use `extract()`** - Explicitly define variables
4. **Don't use `$_REQUEST`** - Use specific `$_GET` or `$_POST`
5. **Don't suppress errors with `@`** - Handle errors properly
6. **Don't use short PHP tags** - Use `<?php`, not `<?`
7. **Don't echo in functions** - Return values instead
8. **Don't use globals unnecessarily** - Pass data explicitly
