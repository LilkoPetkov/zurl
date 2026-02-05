# Zig HTTP CLI - zurl

This project provides a lightweight, fast, and easy-to-use command-line tool for making HTTP requests.

## Building

### Standard Zig Build
To build the project for a small release, run the following command:
```sh
zig build --release=small
```
This will create an executable named `zurl` in the `zig-out/bin/` directory.

### Build and Run with Zep
You can also use the Zep package manager to build and run the application.
```sh
zep runner src/main
```
This command will compile the application and place the `zurl` executable in the `zep-out/bin/` directory. You can then run it from there:
```sh
./zep-out/bin/zurl -u https://www.ziglang.org
```

## Usage

```
./zig-out/bin/zurl [options]
```

### Options

| Flag           | Short | Description                                                                                                   | Argument Type | Required |
|----------------|-------|---------------------------------------------------------------------------------------------------------------|---------------|----------|
| `--help`       | `-h`  | Display this help and exit.                                                                                   | None          | No       |
| `--url`        | `-u`  | The target URL for the HTTP request.                                                                          | `<string>`    | Yes      |
| `--method`     | `-m`  | The HTTP method for the request (e.g., `GET`, `POST`, `put`). Case-insensitive. Defaults to `GET` if omitted. | `<string>`    | No       |
| `--headers_only`| `-I`  | If present, only the response headers will be printed.                                                        | `<boolean>`   | No       |
| `--headers`    | `-H`  | Add custom headers as a comma-separated string (e.g., "key1,value1,key2,value2").                            | `<string>`    | No       |
| `--payload`    | `-d`  | Body payload for the request.                                                                                 | `<string>`    | No       |


## Examples

### Basic GET Request
To perform a simple GET request and print the response body (method defaults to GET):
```sh
./zig-out/bin/zurl -u https://www.ziglang.org
```

### Fetch Only Headers
To request a resource and only display the response headers:
```sh
./zig-out/bin/zurl -u https://www.ziglang.org -I
```

### POST Request with Custom Headers
To send a POST request with custom `Content-Type` and `Authorization` headers (method can be lowercase):
```sh
./zig-out/bin/zurl -u https://api.example.com/items -m post -H "Content-Type,application/json,Authorization,Bearer-token"
```

### POST Request with Payload
To send a POST request with a JSON payload:
```sh
./zig-out/bin/zurl -u https://api.example.com/data -m post -H "Content-Type,application/json" -d '{"key": "value"}'
```
