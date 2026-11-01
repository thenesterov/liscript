(def nil? (lambda (v) (= v nil)))

(def list (lambda () ...))
(def list? (lambda (v) (= "list" (typeof v))))

(def symbol? (lambda (v) (= "symbol" (typeof v))))

(def defracro (racro (name args body) (def name (racro args body))))

(def defn-codegen (lambda (name args body)
  (list def name
    (list lambda args
      (cond
        (nil? body) nil
        (nil? (cdr body)) (car body)
        (cons do body))))))
(defracro defn (name args) (eval (defn-codegen 'name 'args '...)))

(defn intersperse (v xs)
  (cond (nil? xs) nil
        (nil? (cdr xs)) xs
        (cons (car xs) (cons v (intersperse v (cdr xs))))))

(defn not (v) (= v false))

(defracro or () (eval (cons cond (intersperse true '...))))

(defn and-codegen (operands)
  (cond (nil? operands) true
        (list cond (car operands) (and-codegen (cdr operands)) false)))
(defracro and () (eval (and-codegen '...)))

(defn map (f xs)
  (cond (nil? xs) nil
        (cons (f (car xs)) (map f (cdr xs)))))

(defn filter (f xs)
  (cond (nil? xs) nil
        (f (car xs)) (cons (car xs) (filter f (cdr xs)))
        (filter f (cdr xs))))

(defn reduce (f acc xs)
  (cond (nil? xs) acc
        (reduce f (f acc (car xs)) (cdr xs))))
(def foldl reduce)

(defn foldr (f acc xs)
  (cond (nil? xs) acc
        (f (foldr f acc (cdr xs)) (car xs))))

(defn iter (f xs)
  (cond (nil? xs) nil
        (do (f (car xs))
            (iter f (cdr xs)))))

(defn fmap (f xs)
  (cond (list? xs) (cond (nil? xs) nil
                         (cons (fmap f (car xs)) (fmap f (cdr xs))))
        (f xs)))
(def deep-map fmap)

(defn inc (v) (+ v 1))
(defn dec (v) (- v 1))

(defn range (from to)
  (cond (> from to) nil
        (cons from (range (+ 1 from) to))))

(defn take (n lst)
  (cond (<= n 0) nil
  (nil? lst) nil
  (cons (car lst) (take (- n 1) (cdr lst)))))

(defn drop (n lst)
  (cond (<= n 0) lst
  (nil? lst) nil
  (drop (- n 1) (cdr lst))))

(defn contains? (v xs)
  (cond (nil? xs) false
        (= v (car xs)) true
        (contains? v (cdr xs))))

(defn n-times (n f acc)
  (cond (= n 0) acc
        (n-times (- n 1) f (f acc))))

(defn list-ref (i xs)
  (cond (< i 0) (error "index less than 0")
        (nil? xs) (error "index out of range")
        (= i 0) (car xs)
        (list-ref (- i 1) (cdr xs))))

(defn init (len f)
  (map f (range 0 (- len 1))))

(defn repeat (len v)
  (cond (= len 0) nil
        (cons v (repeat (- len 1) v))))

(defn append (xs ys)
  (foldr (lambda (acc v) (cons v acc)) ys xs))

(defn length (xs)
  (reduce (lambda (acc v) (+ 1 acc)) 0 xs))

(defn reverse (xs)
  (reduce (lambda (acc v) (cons v acc)) nil xs))

(defn all (f xs)
  (cond (nil? xs) true
        (f (car xs)) (all f (cdr xs))
        false))

(defn any (f xs)
  (cond (nil? xs) false
        (f (car xs)) true
        (any f (cdr xs))))

(defn t () (print "#t") true)
(defn f () (print "#f") false)
