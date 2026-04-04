{
  lib,
  config,
  ...
}:
let
  cfg = config.dotfiles;

  baseArguments = [
    "--smart-case"
    "--line-number"
    "--follow"
    "--hidden"
    "--color=auto"
    "--max-columns=150"
    "--max-columns-preview"

    # Version control directories
    "--glob=!.git/"
    "--glob=!.svn/"
    "--glob=!.hg/"

    # Build artifacts and dependencies
    "--glob=!node_modules/"
    "--glob=!vendor/"
    "--glob=!target/"
    "--glob=!build/"
    "--glob=!dist/"
    "--glob=!out/"
    "--glob=!.gradle/"
    "--glob=!.m2/"

    # IDE and editor files
    "--glob=!.idea/"
    "--glob=!.vscode/"
    "--glob=!*.swp"
    "--glob=!*.swo"
    "--glob=!*~"
    "--glob=!.DS_Store"

    # Python
    "--glob=!__pycache__/"
    "--glob=!*.pyc"
    "--glob=!*.pyo"
    "--glob=!*.pyd"
    "--glob=!.Python"
    "--glob=!*.egg-info/"
    "--glob=!.pytest_cache/"
    "--glob=!.mypy_cache/"
    "--glob=!.tox/"
    "--glob=!venv/"
    "--glob=!env/"

    # JavaScript/TypeScript
    "--glob=!package-lock.json"
    "--glob=!yarn.lock"
    "--glob=!pnpm-lock.yaml"
    "--glob=!*.min.js"
    "--glob=!*.min.css"
    "--glob=!.next/"
    "--glob=!.nuxt/"

    # Java/Scala
    "--glob=!*.class"
    "--glob=!*.jar"
    "--glob=!*.war"

    # Logs and databases
    "--glob=!*.log"
    "--glob=!*.sqlite"
    "--glob=!*.db"

    # Archives
    "--glob=!*.zip"
    "--glob=!*.tar"
    "--glob=!*.tar.gz"
    "--glob=!*.tgz"
    "--glob=!*.rar"

    # Images and media
    "--glob=!*.jpg"
    "--glob=!*.jpeg"
    "--glob=!*.png"
    "--glob=!*.gif"
    "--glob=!*.ico"
    "--glob=!*.svg"
    "--glob=!*.mp4"
    "--glob=!*.mp3"

    # Documents
    "--glob=!*.pdf"
    "--glob=!*.doc"
    "--glob=!*.docx"
    "--glob=!*.xls"
    "--glob=!*.xlsx"

    # macOS specific
    "--glob=!.Spotlight-V100/"
    "--glob=!.Trashes"
    "--glob=!.fseventsd/"
    "--glob=!.DocumentRevisions-V100/"
    "--glob=!.TemporaryItems/"

    # AWS and cloud
    "--glob=!.aws/"
    "--glob=!.terraform/"
    "--glob=!terraform.tfstate*"

    # Coverage reports
    "--glob=!coverage/"
    "--glob=!.coverage"
    "--glob=!htmlcov/"
  ];

  workArguments = [
    "--glob=!.credentials/"
    "--glob=!credentials.json"
  ];
in
{
  programs.ripgrep = {
    enable = true;
    arguments = baseArguments ++ lib.optionals cfg.work workArguments;
  };
}
