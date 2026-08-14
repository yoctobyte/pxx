class Bus:
    def __init__(self):
        self.sent = 0

    def send(self, msg):
        self.sent = self.sent + 1
        return "bus:" + msg
