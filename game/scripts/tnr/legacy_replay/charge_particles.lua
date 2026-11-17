-- TH15 effect type 1 (407b80/407c10), the emitter behind ANM 508 1.
local Charge = {}
Charge.__index = Charge

local function polar(angle, radius)
    return math.cos(angle) * radius, math.sin(angle) * radius
end

local function unit(x, y)
    local length = math.sqrt(x * x + y * y)
    if length == 0 then return 0, 0 end
    return x / length, y / length
end

local function curve(x0, y0, x1, y1, dx0, dy0, dx1, dy1)
    return { x0 = x0, y0 = y0, x1 = x1, y1 = y1,
        dx0 = dx0, dy0 = dy0, dx1 = dx1, dy1 = dy1 }
end

function Charge.new(random)
    return setmetatable({ random = random, age = 0, particles = {} }, Charge)
end

function Charge:random_offset(radius)
    local angle = self.random(-math.pi, math.pi)
    local distance = self.random(0, radius)
    return polar(angle, distance)
end

function Charge:emit(source, duration)
    local far_x, far_y = polar(source.rotation, 300)
    local near_x, near_y = polar(source.rotation + (source.vars[10035] or 0), 150)
    for index = 1, 4 do
        local vm = source:create_child(index == 4 and 153 or 152)
        if vm then
            local a, b = self:random_offset(150)
            local c, d = self:random_offset(50)
            local x0, y0, x1, y1 = far_x + a, far_y + b, near_x + c, near_y + d
            local ux, uy = unit(x1 - x0, y1 - y0)
            local vx, vy = unit(-x1, -y1)
            vx, vy = unit(ux + vx, uy + vy)
            local end_speed = self.random(200, 400)
            local start_speed = self.random(100, 200)
            local path = curve(x0, y0, x1, y1, ux * start_speed, uy * start_speed,
                vx * end_speed, vy * end_speed)
            vm.vars[10000] = duration
            vm.red, vm.green, vm.blue = source.red, source.green, source.blue
            if index == 4 then
                vm.red, vm.green, vm.blue = (300 - vm.red) % 256, (300 - vm.green) % 256, (300 - vm.blue) % 256
            end
            vm.x, vm.y = x0, y0
            self.particles[#self.particles + 1] = { vm = vm, path = path, age = 0 }
        end
    end
end

function Charge:update(source)
    local duration = math.max(1, source.vars[10000] or 60)
    if self.age < 50 then self:emit(source, duration) end
    local live = {}
    for _, particle in ipairs(self.particles) do
        local vm = particle.vm
        if not vm.finished then
            particle.age = particle.age + 1
            local path = particle.path
            if particle.age == duration + 1 then
                local x, y = self:random_offset(20)
                local dx, dy = self:random_offset(20)
                path = curve(path.x1, path.y1, x, y, path.dx1, path.dy1, dx, dy)
                particle.path = path
            end
            local elapsed = particle.age > duration and particle.age - duration - 1 or particle.age
            local t = math.min(1, elapsed / duration)
            local from, to = (1 + 2*t) * (1 - t)^2, t*t * (3 - 2*t)
            local start_tangent, end_tangent = t * (1 - t)^2, t*t * (t - 1)
            vm.x = path.x0*from + path.x1*to + path.dx0*start_tangent + path.dx1*end_tangent
            vm.y = path.y0*from + path.y1*to + path.dy0*start_tangent + path.dy1*end_tangent
            live[#live + 1] = particle
        end
    end
    self.particles = live
    self.age = self.age + 1
    if #self.particles == 0 and self.age >= 50 then source.charge = nil end
end

return Charge
