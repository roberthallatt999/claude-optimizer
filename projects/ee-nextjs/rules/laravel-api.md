# Laravel API Patterns for Headless ExpressionEngine

These rules MUST be followed when building Laravel API routes that serve as the integration layer between ExpressionEngine (Coilpack) and the Next.js frontend.

## API Route Structure

### Route Organization
- All API routes live in `routes/api.php`
- Prefix all routes with `/v1/` for versioning
- Group related routes with controllers
- Use resource controllers where appropriate

```php
// routes/api.php
use App\Http\Controllers\Api\V1\EntryController;
use App\Http\Controllers\Api\V1\PageController;
use App\Http\Controllers\Api\V1\NavigationController;
use App\Http\Controllers\Api\V1\SearchController;

Route::prefix('v1')->group(function () {
    // Channel entries
    Route::get('/entries/{channel}', [EntryController::class, 'index']);
    Route::get('/entries/{channel}/{slug}', [EntryController::class, 'show']);

    // Pages
    Route::get('/pages/{slug}', [PageController::class, 'show']);

    // Navigation
    Route::get('/navigation/{menu}', [NavigationController::class, 'index']);

    // Search
    Route::get('/search', [SearchController::class, 'index']);

    // Authenticated routes
    Route::middleware('auth:sanctum')->group(function () {
        Route::post('/forms/{form}', [FormController::class, 'submit']);
    });
});
```

## API Controllers

### Controller Structure
- Place API controllers in `app/Http/Controllers/Api/V1/`
- Extend a base `ApiController` for shared logic
- Return `JsonResponse` from all methods
- Use API Resources for response formatting

```php
// app/Http/Controllers/Api/V1/EntryController.php
namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Http\Resources\EntryResource;
use App\Http\Resources\EntryCollection;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class EntryController extends Controller
{
    public function index(Request $request, string $channel): JsonResponse
    {
        $entries = ee('Channel')->getEntries([
            'channel' => $channel,
            'limit' => $request->input('limit', 10),
            'offset' => $request->input('offset', 0),
            'orderby' => $request->input('orderby', 'date'),
            'sort' => $request->input('sort', 'desc'),
            'status' => 'open',
        ]);

        return response()->json(
            new EntryCollection($entries)
        );
    }

    public function show(string $channel, string $slug): JsonResponse
    {
        $entry = ee('Channel')->getEntries([
            'channel' => $channel,
            'url_title' => $slug,
            'limit' => 1,
        ])->first();

        if (!$entry) {
            return response()->json([
                'error' => ['code' => 'NOT_FOUND', 'message' => 'Entry not found']
            ], 404);
        }

        return response()->json([
            'data' => new EntryResource($entry),
        ]);
    }
}
```

## API Resources

### Resource Classes
- Use Laravel API Resources for consistent response formatting
- Define one resource per content type
- Handle nested relationships in resources

```php
// app/Http/Resources/EntryResource.php
namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class EntryResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->entry_id,
            'title' => $this->title,
            'slug' => $this->url_title,
            'date' => $this->entry_date,
            'status' => $this->status,
            'channel' => $this->channel->channel_name,
            'fields' => $this->getCustomFields(),
            'categories' => CategoryResource::collection($this->categories),
            'author' => [
                'id' => $this->author_id,
                'name' => $this->author->screen_name,
            ],
        ];
    }
}
```

### Collection Resources
```php
// app/Http/Resources/EntryCollection.php
namespace App\Http\Resources;

use Illuminate\Http\Resources\Json\ResourceCollection;

class EntryCollection extends ResourceCollection
{
    public function toArray($request): array
    {
        return [
            'data' => $this->collection->map(fn($entry) => new EntryResource($entry)),
            'meta' => [
                'total' => $this->total(),
                'limit' => $request->input('limit', 10),
                'offset' => $request->input('offset', 0),
            ],
        ];
    }
}
```

## Middleware

### CORS Configuration
```php
// config/cors.php
return [
    'paths' => ['api/*'],
    'allowed_methods' => ['*'],
    'allowed_origins' => [
        env('FRONTEND_URL', 'http://localhost:3000'),
    ],
    'allowed_headers' => ['*'],
    'exposed_headers' => [],
    'max_age' => 0,
    'supports_credentials' => true,
];
```

### Rate Limiting
```php
// app/Providers/RouteServiceProvider.php
use Illuminate\Cache\RateLimiting\Limit;
use Illuminate\Support\Facades\RateLimiter;

RateLimiter::for('api', function (Request $request) {
    return Limit::perMinute(60)->by($request->user()?->id ?: $request->ip());
});
```

### Custom API Middleware
```php
// app/Http/Middleware/ApiCacheHeaders.php
namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;

class ApiCacheHeaders
{
    public function handle(Request $request, Closure $next, int $maxAge = 3600)
    {
        $response = $next($request);

        $response->headers->set('Cache-Control', "public, max-age={$maxAge}, s-maxage={$maxAge}");
        $response->headers->set('Vary', 'Accept, Accept-Encoding');

        return $response;
    }
}
```

## Authentication (Sanctum)

### Setup
```php
// config/sanctum.php
return [
    'stateful' => explode(',', env('SANCTUM_STATEFUL_DOMAINS',
        'localhost,localhost:3000,127.0.0.1,127.0.0.1:8000,::1'
    )),
    'guard' => ['web'],
    'expiration' => null,
];
```

### Token-Based Authentication
```php
// API token creation (for external consumers)
Route::post('/v1/auth/token', function (Request $request) {
    $request->validate([
        'email' => 'required|email',
        'password' => 'required',
    ]);

    $user = User::where('email', $request->email)->first();

    if (!$user || !Hash::check($request->password, $user->password)) {
        return response()->json([
            'error' => ['code' => 'INVALID_CREDENTIALS', 'message' => 'Invalid credentials']
        ], 401);
    }

    $token = $user->createToken('api-token')->plainTextToken;

    return response()->json(['data' => ['token' => $token]]);
});
```

## Response Format Standards

### Success Response
```json
{
    "data": { ... },
    "meta": {
        "total": 25,
        "limit": 10,
        "offset": 0
    }
}
```

### Error Response
```json
{
    "error": {
        "code": "VALIDATION_ERROR",
        "message": "The given data was invalid.",
        "details": {
            "field": ["Error message"]
        }
    }
}
```

### Pagination
```json
{
    "data": [ ... ],
    "meta": {
        "total": 100,
        "per_page": 10,
        "current_page": 1,
        "last_page": 10
    },
    "links": {
        "first": "/api/v1/entries/blog?page=1",
        "last": "/api/v1/entries/blog?page=10",
        "prev": null,
        "next": "/api/v1/entries/blog?page=2"
    }
}
```

## Caching

### Response Caching
```php
public function index(Request $request, string $channel): JsonResponse
{
    $cacheKey = "api:entries:{$channel}:" . md5($request->getQueryString());

    $data = Cache::remember($cacheKey, 3600, function () use ($request, $channel) {
        $entries = ee('Channel')->getEntries([
            'channel' => $channel,
            'limit' => $request->input('limit', 10),
        ]);

        return new EntryCollection($entries);
    });

    return response()->json($data);
}
```

### Cache Invalidation
```php
// Clear API cache when content changes
Cache::tags(['api', "channel:{$channel}"])->flush();
```

## Checklist

- [ ] All API routes are versioned (`/v1/`)
- [ ] API Resources used for response formatting
- [ ] CORS configured for frontend origin
- [ ] Rate limiting applied
- [ ] Authentication via Sanctum where needed
- [ ] Response format is consistent (data/meta/error)
- [ ] Caching implemented for expensive queries
- [ ] Error responses include meaningful codes
- [ ] Input validation on all endpoints
