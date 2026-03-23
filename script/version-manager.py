#!/usr/bin/env python3
"""
版本管理器
用于生成和记录规则文件版本信息
"""

import json
import os
from datetime import datetime
from pathlib import Path

class VersionManager:
    def __init__(self, version_file="version.json"):
        self.version_file = Path(version_file)
        self.version_data = self.load_version()

    def load_version(self):
        """加载版本信息"""
        if self.version_file.exists():
            try:
                with open(self.version_file, 'r', encoding='utf-8') as f:
                    return json.load(f)
            except Exception as e:
                print(f"加载版本文件失败: {e}")
                return self.create_default_version()
        return self.create_default_version()

    def create_default_version(self):
        """创建默认版本信息"""
        return {
            "project": "MyRules",
            "version": "1.0.0",
            "created_at": datetime.now().isoformat(),
            "last_updated": datetime.now().isoformat(),
            "files": {}
        }

    def save_version(self):
        """保存版本信息"""
        self.version_data["last_updated"] = datetime.now().isoformat()
        with open(self.version_file, 'w', encoding='utf-8') as f:
            json.dump(self.version_data, f, indent=2, ensure_ascii=False)

    def add_file_version(self, filename, domain_count, source_file):
        """添加文件版本信息"""
        file_info = {
            "filename": filename,
            "domain_count": domain_count,
            "source_file": source_file,
            "created_at": datetime.now().isoformat(),
            "version": self._generate_file_version(filename)
        }
        self.version_data["files"][filename] = file_info
        self.save_version()

    def _generate_file_version(self, filename):
        """生成文件版本号"""
        if filename in self.version_data["files"]:
            old_version = self.version_data["files"][filename].get("version", "1.0.0")
            major, minor, patch = map(int, old_version.split('.'))
            patch += 1
            return f"{major}.{minor}.{patch}"
        return "1.0.0"

    def get_file_version(self, filename):
        """获取文件版本信息"""
        return self.version_data["files"].get(filename)

    def get_all_files(self):
        """获取所有文件版本信息"""
        return self.version_data["files"]

    def print_version_info(self):
        """打印版本信息"""
        print(f"项目: {self.version_data['project']}")
        print(f"版本: {self.version_data['version']}")
        print(f"创建时间: {self.version_data['created_at']}")
        print(f"最后更新: {self.version_data['last_updated']}")
        print(f"\n文件列表:")
        for filename, info in self.version_data["files"].items():
            print(f"  - {filename} (v{info['version']}, {info['domain_count']} domains)")

def main():
    """主函数"""
    vm = VersionManager()
    vm.print_version_info()

if __name__ == "__main__":
    main()
