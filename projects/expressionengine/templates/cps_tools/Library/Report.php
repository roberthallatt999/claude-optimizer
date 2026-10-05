<?php

namespace CPS\Tools\Library;

/**
 * Collects schema-check results and handles baseline write/compare.
 *
 * A result is {check, subject, subject_type, status: pass|warn|fail, message}.
 */
class Report
{
    /**
     * @var array<int, array<string, string>>
     */
    private array $results = [];

    /**
     * @param string $check
     * @param string $subject
     * @param string $status pass|warn|fail
     * @param string $message
     * @param string $subjectType fieldtype short name for field/column subjects, else ''
     * @return void
     */
    public function add(string $check, string $subject, string $status, string $message, string $subjectType = ''): void
    {
        $this->results[] = [
            'check' => $check,
            'subject' => $subject,
            'subject_type' => $subjectType,
            'status' => $status,
            'message' => $message,
        ];
    }

    /**
     * @return array<int, array<string, string>>
     */
    public function results(): array
    {
        return $this->results;
    }

    /**
     * @return array{pass: int, warn: int, fail: int}
     */
    public function summary(): array
    {
        $summary = ['pass' => 0, 'warn' => 0, 'fail' => 0];
        foreach ($this->results as $result) {
            $summary[$result['status']]++;
        }
        return $summary;
    }

    /**
     * @param array<string, string> $result
     * @return string
     */
    public static function fingerprint(array $result): string
    {
        return $result['check'] . '|' . $result['subject'] . '|' . $result['message'];
    }

    /**
     * Failures whose fingerprint is absent from the baseline.
     *
     * @param array<int, array<string, string>> $baselineResults
     * @return array<int, array<string, string>>
     */
    public function compare(array $baselineResults): array
    {
        $known = [];
        foreach ($baselineResults as $result) {
            $known[self::fingerprint($result)] = true;
        }

        $new = [];
        foreach ($this->results as $result) {
            if ($result['status'] === 'fail' && !isset($known[self::fingerprint($result)])) {
                $new[] = $result;
            }
        }
        return $new;
    }

    /**
     * @param string $path
     * @return void
     */
    public function writeBaseline(string $path): void
    {
        $dir = dirname($path);
        if (!is_dir($dir) && !mkdir($dir, 0775, true) && !is_dir($dir)) {
            throw new \RuntimeException('Cannot create baseline directory: ' . $dir);
        }
        $json = json_encode(['results' => $this->results], JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES);
        if (file_put_contents($path, $json) === false) {
            throw new \RuntimeException('Cannot write baseline: ' . $path);
        }
    }

    /**
     * @param string $path
     * @return array<int, array<string, string>>
     */
    public static function readBaseline(string $path): array
    {
        if (!is_file($path)) {
            throw new \RuntimeException('Baseline not found: ' . $path);
        }
        $data = json_decode((string) file_get_contents($path), true);
        if (!is_array($data) || !isset($data['results']) || !is_array($data['results'])) {
            throw new \RuntimeException('Baseline is not valid: ' . $path);
        }
        return $data['results'];
    }
}
