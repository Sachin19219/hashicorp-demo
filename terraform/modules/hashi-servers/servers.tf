resource "aws_security_group" "hashi_demo_server" {
    name = "hashi_demo_server_${var.platform}"
    description = "Server: Consul, Nomad and Vault internal traffic + maintenance."

    // These are for internal traffic
    ingress {
        from_port = 0
        to_port = 65535
        protocol = "tcp"
        self = true
    }

    ingress {
        from_port = 0
        to_port = 65535
        protocol = "udp"
        self = true
    }

    ingress {
        from_port = 8200
        to_port = 8200
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    ingress {
        from_port = 8300
        to_port = 8302
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    ingress {
        from_port = 8400
        to_port = 8400
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    ingress {
        from_port = 4646
        to_port = 4648
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    ingress {
        from_port = 8500
        to_port = 8500
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    // These are for maintenance
    ingress {
        from_port = 22
        to_port = 22
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    // This is for outbound internet access
    egress {
        from_port = 0
        to_port = 0
        protocol = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }
}

data "template_file" "nomad_server_conf" {
    template = "${file("${path.module}/scripts/nomad_server.conf.tpl")}"
}

resource "aws_instance" "server" {
    ami = "${var.ami}"
    instance_type = "${var.instance_type}"
    key_name = "${var.key_name}"
    count = "${var.server_count}"
    security_groups = ["${aws_security_group.hashi_demo_server.name}"]

    connection {
        user = "${var.user}"
        private_key = "${file("${var.key_path}")}"
    }

    #Instance tags
    tags {
        Name = "${var.tagName}-server-${count.index}"
    }

    provisioner "remote-exec" {
        inline = [
            "sudo stop nomad",
            "sudo rm /var/log/nomad.log",
            "sudo stop vault",
            "sudo rm /var/log/vault.log",
            "sudo stop consul",
            "sudo rm /var/log/consul.log",
            "sudo echo 'CONSUL_FLAGS=\"-server -bootstrap-expect=${var.server_count} -ui -join=${aws_instance.server.0.private_dns} -data-dir=/opt/consul/data -client=0.0.0.0\"' | sudo tee /etc/service/consul > /dev/null",
            "sudo sed -i s/CONSUL_ADDRESS/${aws_instance.server.0.private_ip}/g /usr/local/etc/vault_config.json",
            "sudo echo '${data.template_file.nomad_server_conf.rendered}' | sudo tee -a /usr/local/etc/nomad_config.json > /dev/null",
            "sudo sed -i s/CONSUL_ADDRESS/${aws_instance.server.0.private_ip}/g /usr/local/etc/nomad_config.json",
            "sudo sed -i s/SERVER_COUNT/${var.server_count}/g /usr/local/etc/nomad_config.json",
            "sudo sed -i s/PRIVATE_IP/${self.private_ip}/g /usr/local/etc/nomad_config.json",
            "echo Starting Consul...",
            "sudo start consul",
            "sleep 20",
            "sudo start vault",
            "sleep 20",
            "sudo start nomad"
        ]    
    }
}

resource "null_resource" "vault_init" {
  depends_on = ["aws_instance.server"]

  triggers {
      server_instance_ids = "${join(",", aws_instance.server.*.id)}"
  }

  count = "${var.server_count}"

  connection {
      host = "${element(aws_instance.server.*.public_ip, count.index)}"
      user = "${var.user}"
      private_key = "${file("${var.key_path}")}"
  }

  provisioner "file" {
    source = "${path.module}/scripts/init_vault.sh"
    destination = "/tmp/init_vault.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/init_vault.sh",
      "/tmp/init_vault.sh"
    ]
  }
}

resource "null_resource" "upload_app_url" {
  depends_on = ["null_resource.vault_init"]

  triggers {
      server_instance_id = "${aws_instance.server.0.id}"
  }

  connection {
    host = "${aws_instance.server.0.public_ip}"
    user = "${var.user}"
    private_key = "${file("${var.key_path}")}"
  }

  provisioner "remote-exec" {
    inline = [
      "export VAULT_ADDR=http://127.0.0.1:8200",
      "vault write secret/${var.vault_app_name} password=${var.vault_app_password}",
      "curl -X PUT -d \"${var.app_download_url}\" http://${aws_instance.server.0.private_ip}:8500/v1/kv/service/app/hashiapp_springboot_demo_url"
    ]
  }
}