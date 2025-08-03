# Contributing to Sammelkarten

We welcome contributions to the Sammelkarten project! This document provides guidelines for contributing.

## How to Contribute

### Reporting Issues

If you find a bug or have a feature request:

1. Check if the issue already exists in our [issue tracker](https://github.com/Razue/sammelkarten/issues)
2. If not, create a new issue with:
   - A clear and descriptive title
   - A detailed description of the problem or feature request
   - Steps to reproduce (for bugs)
   - Expected vs actual behavior
   - Your environment (OS, Elixir version, etc.)

### Development Setup

1. Fork the repository
2. Clone your fork:
   ```bash
   git clone https://github.com/YOUR_USERNAME/sammelkarten.git
   cd sammelkarten
   ```
3. Install dependencies:
   ```bash
   mix deps.get
   ```
4. Set up the database (if applicable):
   ```bash
   mix ecto.setup
   ```
5. Start the development server:
   ```bash
   mix phx.server
   ```

### Making Changes

1. Create a new branch for your feature or bugfix:
   ```bash
   git checkout -b feature/your-feature-name
   ```
2. Make your changes
3. Add tests for your changes
4. Ensure all tests pass:
   ```bash
   mix test
   ```
5. Check code formatting:
   ```bash
   mix format --check-formatted
   ```
6. Commit your changes with a clear commit message
7. Push to your fork and create a pull request

### Pull Request Guidelines

- Keep pull requests focused on a single feature or bugfix
- Include tests for new functionality
- Update documentation as needed
- Follow the existing code style
- Write clear commit messages
- Reference any related issues in your PR description

### Code Style

- Follow standard Elixir formatting (use `mix format`)
- Write clear, self-documenting code
- Add comments for complex logic
- Follow Phoenix conventions for web-related code

### Testing

- Write tests for new features and bug fixes
- Ensure all existing tests continue to pass
- Aim for good test coverage

## Code of Conduct

This project follows a Code of Conduct. By participating, you are expected to uphold this code. Please be respectful and constructive in all interactions.

## Getting Help

If you need help:
- Check the existing documentation
- Search existing issues
- Create a new issue with the "question" label
- Join our discussions

Thank you for contributing to Sammelkarten!
