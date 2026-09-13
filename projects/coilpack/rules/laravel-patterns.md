---
paths:
  - "**/*.php"
  - "routes/**"
  - "config/**"
---

# Laravel + Coilpack Patterns

These rules MUST be followed when developing with Laravel and Coilpack.

## Blade Templates

### Blade Syntax
```blade
@extends('layouts.app')

@section('content')
  <h1>{{ $title }}</h1>
@endsection
```

## Eloquent ORM

### Query Optimization
```php
// Eager loading
$posts = Post::with('author', 'tags')->get();

// Only needed columns
$users = User::select('id', 'name')->get();
```

## Livewire Components

### Component Structure
```php
namespace App\Http\Livewire;

use Livewire\Component;

class SearchForm extends Component
{
    public $query = '';

    public function search()
    {
        // Search logic
    }

    public function render()
    {
        return view('livewire.search-form');
    }
}
```

## Checklist

- [ ] Blade directives used correctly
- [ ] Eloquent queries are optimized
- [ ] Livewire components follow conventions
